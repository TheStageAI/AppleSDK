"""The ``thestage-host`` process and the connection to it.

The SDK runs natively in a signed helper the wheel ships
(``thestage_sdk/_bin/thestage-host``); Python only sends calls and reads
events, so inference speed is the native speed. One host per Python
process, started on first use and stopped at exit.
"""

from __future__ import annotations

import asyncio
import atexit
import contextlib
import itertools
import os
import shutil
import tempfile
from pathlib import Path

from ._wire import Frame, read_frame


# ----------------------------------------------------------------------------------------
# SDKError
# ----------------------------------------------------------------------------------------
class SDKError(RuntimeError):
    """
    A call failed in the SDK or the bridge.

    Attributes
    ----------
    code: str
        The error's name, e.g. ``INVALID_PARAM``, ``tokenValidationFailed``,
        ``AUDIO_CAPTURE_PERMISSION_DENIED``.
    message: str
        What went wrong.
    """

    # Constructor
    # ------------------------------------------------------------------------------------
    def __init__(self, code: str, message: str):
        super().__init__(f"{code}: {message}")
        self.code = code
        self.message = message


# ----------------------------------------------------------------------------------------
# Host binary
# ----------------------------------------------------------------------------------------
def host_binary() -> Path:
    """
    Where ``thestage-host`` is.

    Returns
    -------
    path: pathlib.Path
        ``THESTAGE_HOST_BIN`` when set, else the binary inside the wheel.

    Raises
    ------
    FileNotFoundError
        Neither exists.
    """
    override = os.environ.get("THESTAGE_HOST_BIN")
    if override:
        return Path(override)
    bundled = Path(__file__).parent / "_bin" / "thestage-host"
    if bundled.exists():
        return bundled
    raise FileNotFoundError(
        "thestage-host not found: install the thestage_sdk wheel for macOS arm64, "
        "or set THESTAGE_HOST_BIN"
    )


# ----------------------------------------------------------------------------------------
# Stream
# ----------------------------------------------------------------------------------------
class Stream:
    """
    The events of one bridge stream, as an async iterator of ``Frame``.

    Attributes
    ----------
    id: str
        The stream's handle.
    """

    # Constructor
    # ------------------------------------------------------------------------------------
    def __init__(self, host: Host, stream_id: str):
        self.id = stream_id
        self._host = host
        self._queue: asyncio.Queue = asyncio.Queue()

    # Public Methods
    # ------------------------------------------------------------------------------------
    def __aiter__(self):
        return self

    async def __anext__(self) -> Frame:
        frame = await self._queue.get()
        if frame is None:
            raise StopAsyncIteration
        if frame.header.get("t") == "end":
            self._host._streams.pop(self.id, None)
            error = frame.header.get("e")
            if error:
                raise SDKError(error.get("code", "ERROR"), error.get("message", ""))
            raise StopAsyncIteration
        return frame

    # Private Methods
    # ------------------------------------------------------------------------------------
    def _push(self, frame: Frame | None) -> None:
        """
        Queue a frame for the iterator; ``None`` ends it without an error.

        Parameters
        ----------
        frame: Frame or None
        """
        self._queue.put_nowait(frame)


# ----------------------------------------------------------------------------------------
# Host
# ----------------------------------------------------------------------------------------
class Host:
    """
    The running ``thestage-host`` and its socket; one per process (``host()``).

    The host serves one connection and exits when it closes, so the connection
    belongs to the event loop that opened it. A call from another loop, or after
    the host went away, starts a fresh host; handles from the old one are gone.
    """

    # Constructor
    # ------------------------------------------------------------------------------------
    def __init__(self) -> None:
        self._process: asyncio.subprocess.Process | None = None
        self._reader: asyncio.StreamReader | None = None
        self._writer: asyncio.StreamWriter | None = None
        self._ids = itertools.count(1)
        self._pending: dict[int, asyncio.Future] = {}
        self._streams: dict[str, Stream] = {}
        self._buffered: dict[str, list[Frame]] = {}
        self._model_handles: dict[str, set[str]] = {}
        self._read_task: asyncio.Task | None = None
        self._stdout_task: asyncio.Task | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._lock: asyncio.Lock | None = None
        self._lock_loop: asyncio.AbstractEventLoop | None = None
        self._dir: str | None = None
        self._atexit = False

    # Public Methods
    # ------------------------------------------------------------------------------------
    async def start(self) -> None:
        """
        Start the host and connect, once per event loop; later calls on the same
        loop return at once while the host is alive.

        Raises
        ------
        SDKError
            The host did not report ready within ``THESTAGE_HOST_READY_TIMEOUT``
            seconds (default 60), or exited first.
        """
        loop = asyncio.get_running_loop()
        if self._connected(loop):
            return
        if self._lock is None or self._lock_loop is not loop:
            # An asyncio.Lock belongs to the loop it was first used on.
            self._lock = asyncio.Lock()
            self._lock_loop = loop
        async with self._lock:
            if self._connected(loop):
                return
            if self._writer is not None or self._process is not None:
                # Another loop's connection, or a host that went away.
                self._fail_all(SDKError("HOST", "thestage-host was restarted"))
                self._teardown()
            await self._spawn(loop)

    def close(self) -> None:
        """
        Close the socket and stop the host (also at interpreter exit).
        """
        self._teardown()

    async def call(self, method: str, body: bytes = b"", **params) -> Frame:
        """
        Make one call and wait for its result.

        Parameters
        ----------
        method: str
            The bridge method, e.g. ``"llm.infer"``.
        body: bytes
            Raw bytes sent with the call (PCM, images).
        **params
            The call's parameters; ``None`` values are left out.

        Returns
        -------
        frame: Frame
            The ``res`` frame: ``header["r"]`` is the result, ``body`` its bytes.

        Raises
        ------
        SDKError
            The call failed, or the host went away before it answered.
        """
        await self.start()
        writer = self._writer
        if writer is None:
            raise SDKError("HOST", "thestage-host connection lost")
        call_id = next(self._ids)
        future = asyncio.get_running_loop().create_future()
        self._pending[call_id] = future
        params = {k: v for k, v in params.items() if v is not None}
        try:
            writer.write(
                Frame(
                    {"t": "call", "id": call_id, "m": method, "p": params}, body
                ).encode()
            )
            await writer.drain()
        except (ConnectionError, RuntimeError) as error:
            self._pending.pop(call_id, None)
            raise SDKError("HOST", f"thestage-host connection lost: {error}") from error
        return await future

    async def open_stream(
        self, method: str, body: bytes = b"", **params
    ) -> tuple[Stream, dict]:
        """
        Make a call that starts a stream.

        Parameters
        ----------
        method: str
            The bridge method, e.g. ``"llm.infer_stream"``.
        body: bytes
            Raw bytes sent with the call.
        **params
            The call's parameters.

        Returns
        -------
        stream: Stream
            Its events, including any that arrived before this returned.
        result: dict
            The call's result.
        """
        frame = await self.call(method, body, **params)
        result = frame.header.get("r", {})
        return self.attach_stream(result["stream"]), result

    def track(self, model_name: str, handle: str) -> None:
        """
        Remember that ``handle`` is a model loaded under ``model_name``, so
        ``release_model`` can drop it.

        Parameters
        ----------
        model_name: str
        handle: str
        """
        self._model_handles.setdefault(model_name, set()).add(handle)

    async def release_model(self, model_name: str) -> None:
        """
        Drop the host's handles to the models loaded under ``model_name``. Until
        then a stopped model's memory stays with the handle.

        Parameters
        ----------
        model_name: str
        """
        for handle in self._model_handles.pop(model_name, set()):
            await self.call("sdk.release", handle=handle)

    def attach_stream(self, stream_id: str) -> Stream:
        """
        Read the events of a stream another call returned the handle of.

        Parameters
        ----------
        stream_id: str

        Returns
        -------
        stream: Stream
            Its events, including any that arrived before this call.
        """
        stream = Stream(self, stream_id)
        self._streams[stream.id] = stream
        for early in self._buffered.pop(stream.id, []):
            stream._push(early)
        return stream

    # Private Methods
    # ------------------------------------------------------------------------------------
    def _connected(self, loop: asyncio.AbstractEventLoop) -> bool:
        return (
            self._writer is not None
            and self._loop is loop
            and self._read_task is not None
            and not self._read_task.done()
        )

    async def _spawn(self, loop: asyncio.AbstractEventLoop) -> None:
        """
        Start a host process and connect to it; clean up everything on failure.

        Parameters
        ----------
        loop: asyncio.AbstractEventLoop
            The running loop the connection belongs to.
        """
        self._dir = tempfile.mkdtemp(prefix="thestage-")
        socket_path = os.path.join(self._dir, "host.sock")
        timeout = float(os.environ.get("THESTAGE_HOST_READY_TIMEOUT", "60"))
        try:
            self._process = await asyncio.create_subprocess_exec(
                str(host_binary()),
                "--socket",
                socket_path,
                stdout=asyncio.subprocess.PIPE,
            )
            try:
                line = await asyncio.wait_for(self._process.stdout.readline(), timeout)
            except asyncio.TimeoutError:
                raise SDKError(
                    "HOST", f"thestage-host did not report ready in {timeout:g} s"
                ) from None
            ready = line.decode(errors="replace")
            if not ready.startswith("READY"):
                raise SDKError("HOST", f"thestage-host did not start: {ready!r}")
            self._reader, self._writer = await asyncio.open_unix_connection(socket_path)
        except BaseException:
            self._teardown()
            raise
        self._loop = loop
        # Keep reading stdout so host prints never fill the pipe and block it.
        self._stdout_task = loop.create_task(self._drain_stdout(self._process))
        self._read_task = loop.create_task(self._read_loop(self._reader))
        if not self._atexit:
            atexit.register(self.close)
            self._atexit = True

    @staticmethod
    async def _drain_stdout(process: asyncio.subprocess.Process) -> None:
        # Ends at EOF (the host exited) or when the loop tears the pipe down.
        with contextlib.suppress(OSError, ValueError, RuntimeError):
            while await process.stdout.read(1 << 16):
                pass

    def _fail_all(self, error: SDKError) -> None:
        """
        Fail every waiting call and end every open stream with ``error``.

        Parameters
        ----------
        error: SDKError
        """
        pending, self._pending = self._pending, {}
        streams, self._streams = self._streams, {}
        self._buffered = {}
        for future in pending.values():
            if not future.done():
                try:
                    future.set_exception(error)
                except RuntimeError:
                    # The future's loop is closed; nobody is waiting on it.
                    pass
        end = {"code": error.code, "message": error.message}
        for stream in streams.values():
            try:
                stream._push(Frame({"t": "end", "s": stream.id, "e": end}))
            except RuntimeError:
                pass

    def _teardown(self) -> None:
        """
        Drop the connection, stop the process and remove the socket directory, so the
        next call starts a fresh host. Model handles of the old host are forgotten.
        """
        writer, self._writer = self._writer, None
        self._reader = None
        if writer is not None:
            # The loop may already be closed (interpreter exit, another loop's
            # connection); the host exits on its own when the socket goes away.
            try:
                writer.close()
            except RuntimeError:
                pass
        process, self._process = self._process, None
        if process is not None and process.returncode is None:
            try:
                process.kill()
            except (ProcessLookupError, RuntimeError):
                pass
        current = None
        try:
            current = asyncio.current_task()
        except RuntimeError:
            pass
        for task in (self._read_task, self._stdout_task):
            if task is not None and task is not current and not task.done():
                try:
                    task.cancel()
                except RuntimeError:
                    pass
        self._read_task = None
        self._stdout_task = None
        self._loop = None
        self._model_handles = {}
        if self._dir:
            shutil.rmtree(self._dir, ignore_errors=True)
            self._dir = None

    async def _read_loop(self, reader: asyncio.StreamReader) -> None:
        try:
            while True:
                frame = await read_frame(reader)
                kind = frame.header.get("t")
                if kind in ("res", "err"):
                    future = self._pending.pop(frame.header.get("id"), None)
                    if future is None or future.done():
                        continue
                    if kind == "res":
                        future.set_result(frame)
                    else:
                        e = frame.header.get("e", {})
                        future.set_exception(
                            SDKError(e.get("code", "ERROR"), e.get("message", ""))
                        )
                elif kind in ("ev", "end"):
                    stream_id = frame.header.get("s")
                    stream = self._streams.get(stream_id)
                    if stream is None:
                        self._buffered.setdefault(stream_id, []).append(frame)
                    else:
                        stream._push(frame)
        except asyncio.CancelledError:
            raise
        except (asyncio.IncompleteReadError, ConnectionError):
            error = SDKError("HOST", "thestage-host closed the connection")
        except Exception as exc:  # noqa: BLE001 - any failure must release waiters
            error = SDKError("HOST", f"thestage-host connection failed: {exc!r}")
        if self._reader is reader:
            # Streams end with the error, not as completed; the next call respawns.
            self._fail_all(error)
            self._teardown()


# ----------------------------------------------------------------------------------------
# The process's host
# ----------------------------------------------------------------------------------------
_host: Host | None = None


def host() -> Host:
    """
    The process's host connection, created on first use.

    Returns
    -------
    host: Host
    """
    global _host
    if _host is None:
        _host = Host()
    return _host
