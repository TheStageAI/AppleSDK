"""``WS /v1/realtime?intent=transcription``: OpenAI's Realtime transcription
protocol over ``ASREngine``.

The client streams PCM (``input_audio_buffer.append``); the engine's VAD,
streaming recogniser and turn detector produce turns, sent as OpenAI events:
``input_audio_buffer.speech_started``, ``…transcription.delta`` (committed
text as it grows), then at the turn's end ``speech_stopped``, ``committed`` and
``…transcription.completed`` (the formatted transcript). TheStage extension
``thestage.transcription.partial`` carries the live hypothesis and speaker.

``&source=microphone|system|meeting`` captures on this Mac instead: the client
sends no audio and gets the same events.
"""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import secrets

import numpy as np
from aiohttp import WSMsgType, web

from .._host import SDKError
from ..audio import ASREngine, ASRStreamingConfig, TSAgentConfig, TSAudioConfig
from .formats import float32_from_s16le
from .registry import ModelRegistry

log = logging.getLogger("thestage_sdk.server")

_CAPTURE_SOURCES = {"microphone", "system", "meeting"}


# ----------------------------------------------------------------------------------------
# Routes
# ----------------------------------------------------------------------------------------
def setup(app: web.Application) -> None:
    """
    Register ``/v1/realtime``.

    Parameters
    ----------
    app: aiohttp.web.Application
    """
    app["realtime_lock"] = asyncio.Lock()
    app.router.add_get("/v1/realtime", realtime)


# ----------------------------------------------------------------------------------------
# TranscriptionSession
# ----------------------------------------------------------------------------------------
def _event_id() -> str:
    """
    Returns
    -------
    event_id: str
    """
    return "event_" + secrets.token_hex(8)


class TranscriptionSession:
    """
    One client, one engine; turns become OpenAI items.

    Parameters
    ----------
    ws: aiohttp.web.WebSocketResponse
    app: aiohttp.web.Application
    source: str or None
        ``"microphone"``, ``"system"`` or ``"meeting"`` to capture on the Mac;
        ``None`` takes pushed audio.
    """

    # Constructor
    # ------------------------------------------------------------------------------------
    def __init__(
        self, ws: web.WebSocketResponse, app: web.Application, source: str | None
    ):
        self.ws = ws
        self.app = app
        self.source = source
        self.rate = 24_000
        self.language = "auto"
        self.model: str | None = None
        self.engine: ASREngine | None = None
        self._pump: asyncio.Task | None = None
        self._items: dict[int, str] = {}
        self._sent: dict[int, str] = {}
        self._previous_item: str | None = None
        self._beta = False

    # Public Methods
    # ------------------------------------------------------------------------------------
    async def send(self, event: dict) -> None:
        """
        Parameters
        ----------
        event: dict
            Sent with a new ``event_id``, unless the socket closed.
        """
        if not self.ws.closed:
            await self.ws.send_json({"event_id": _event_id(), **event})

    async def error(self, message: str, code: str, event_id: str | None = None) -> None:
        """
        Parameters
        ----------
        message: str
        code: str
        event_id: str, optional
            The client event at fault.
        """
        await self.send(
            {
                "type": "error",
                "error": {
                    "type": "invalid_request_error",
                    "code": code,
                    "message": message,
                    "event_id": event_id,
                },
            }
        )

    async def created(self) -> None:
        """
        Send ``session.created``.
        """
        await self.send({"type": "session.created", "session": self._session()})

    async def update(self, event: dict) -> None:
        """
        Apply ``session.update`` or ``transcription_session.update``.

        Parameters
        ----------
        event: dict
        """
        self._beta = event["type"].startswith("transcription_session")
        session = event.get("session") or {}
        if self._beta:
            transcription = session.get("input_audio_transcription") or {}
            audio_format = session.get("input_audio_format", "pcm16")
            if audio_format != "pcm16":
                return await self.error(
                    f"input_audio_format {audio_format} is not supported; use pcm16",
                    "unsupported_audio_format",
                    event.get("event_id"),
                )
        else:
            audio_input = (session.get("audio") or {}).get("input") or {}
            transcription = audio_input.get("transcription") or {}
            audio_format = audio_input.get("format") or {}
            if audio_format.get("type", "audio/pcm") != "audio/pcm":
                return await self.error(
                    f"format {audio_format.get('type')} is not supported; use audio/pcm",
                    "unsupported_audio_format",
                    event.get("event_id"),
                )
            self.rate = int(audio_format.get("rate", self.rate))
        if self.engine is None:
            self.language = transcription.get("language") or self.language
            self.model = transcription.get("model") or self.model
        kind = "transcription_session.updated" if self._beta else "session.updated"
        await self.send({"type": kind, "session": self._session()})

    async def append(self, event: dict) -> None:
        """
        Push ``input_audio_buffer.append`` audio, starting the engine on first use.

        Parameters
        ----------
        event: dict
        """
        if self.source:
            return await self.error(
                "this session captures on the Mac; it takes no audio",
                "invalid_value",
                event.get("event_id"),
            )
        await self.start()
        pcm = float32_from_s16le(base64.b64decode(event.get("audio", "")))
        await self.engine.push(pcm, sample_rate=self.rate)

    async def commit(self, event: dict) -> None:
        """
        End the open turn now: the engine's own endpoint, reached by two seconds of
        silence (long enough for the VAD hangover and SmartTurn).

        Parameters
        ----------
        event: dict
        """
        if self.engine and not self.source:
            silence = np.zeros(2 * self.rate, dtype=np.float32)
            await self.engine.push(silence, sample_rate=self.rate)

    async def start(self) -> None:
        """
        Create and start the engine, and pump its turns.
        """
        if self.engine is not None:
            return
        registry: ModelRegistry = self.app["registry"]
        config = self.app["config"]
        audio = (
            TSAudioConfig(source="push")
            if not self.source
            else TSAudioConfig(
                source=self.source,
                aec=config.audio.aec if self.source == "microphone" else None,
            )
        )
        engine_config = TSAgentConfig(
            stt=registry.resolve("asr", self.model),
            vad=config.vad or "TheStageAI/silero-vad",
            language=self.language,
            turn_detector=config.turn_detector,
            asr_streaming_config=ASRStreamingConfig(algorithm=config.streaming_algorithm),
            audio=audio,
        )
        self.engine = await registry.engine(engine_config)
        turns = await self.engine.turns()
        self._pump = asyncio.create_task(self._turns(turns))
        await self.engine.start()

    async def stop(self) -> None:
        """
        Stop the engine, wait for the last turns and free the engine in the host.
        """
        if self.engine is not None:
            try:
                await self.engine.stop()
            except SDKError as error:
                log.warning("engine stop: %s", error)
        if self._pump is not None:
            try:
                await asyncio.wait_for(self._pump, 5)
            except (asyncio.TimeoutError, asyncio.CancelledError):
                self._pump.cancel()
        engine, self.engine = self.engine, None
        if engine is not None:
            # Each session creates its own engine; without this every
            # connection left one EngineHandle (models, audio graph) behind.
            try:
                await engine.close()
            except SDKError as error:
                log.warning("engine close: %s", error)

    # Private Methods
    # ------------------------------------------------------------------------------------
    def _session(self) -> dict:
        """
        Returns
        -------
        session: dict
            The session object in the protocol version the client uses.
        """
        transcription = {"model": self.model or "whisper-1", "language": self.language}
        if self._beta:
            return {
                "object": "realtime.transcription_session",
                "input_audio_format": "pcm16",
                "input_audio_transcription": transcription,
                "turn_detection": {"type": "server_vad"},
            }
        return {
            "type": "transcription",
            "audio": {
                "input": {
                    "format": {"type": "audio/pcm", "rate": self.rate},
                    "transcription": transcription,
                    "turn_detection": {"type": "server_vad"},
                }
            },
        }

    async def _turns(self, turns) -> None:
        """
        Parameters
        ----------
        turns: async iterator of ASRTurn
        """
        async for turn in turns:
            await self._on_turn(turn)

    async def _on_turn(self, turn) -> None:
        """
        One turn update as OpenAI events: ``speech_started`` on its first update,
        ``delta`` as committed text grows, the ``thestage.transcription.partial``
        extension every time, and at its end ``speech_stopped``, ``committed`` and
        ``completed``.

        Parameters
        ----------
        turn: ASRTurn
        """
        order = turn.turn_order
        item = self._items.get(order)
        if item is None:
            item = self._items[order] = "item_" + secrets.token_hex(10)
            self._sent[order] = ""
            start_ms = int(turn.words[0].t0 * 1000) if turn.words else 0
            await self.send(
                {
                    "type": "input_audio_buffer.speech_started",
                    "audio_start_ms": start_ms,
                    "item_id": item,
                }
            )
        committed = turn.committed.strip()
        sent = self._sent[order]
        if committed.startswith(sent) and len(committed) > len(sent):
            await self.send(
                {
                    "type": "conversation.item.input_audio_transcription.delta",
                    "item_id": item,
                    "content_index": 0,
                    "delta": committed[len(sent) :],
                }
            )
            self._sent[order] = committed
        await self.send(
            {
                "type": "thestage.transcription.partial",
                "item_id": item,
                "committed": turn.committed,
                "hypothesis": turn.hypothesis,
                "speaker_id": turn.speaker_id,
                "language": turn.language,
            }
        )
        if turn.end_of_turn:
            end_ms = int(turn.words[-1].t1 * 1000) if turn.words else 0
            await self.send(
                {
                    "type": "input_audio_buffer.speech_stopped",
                    "audio_end_ms": end_ms,
                    "item_id": item,
                }
            )
            await self.send(
                {
                    "type": "input_audio_buffer.committed",
                    "item_id": item,
                    "previous_item_id": self._previous_item,
                }
            )
            await self.send(
                {
                    "type": "conversation.item.input_audio_transcription.completed",
                    "item_id": item,
                    "content_index": 0,
                    "transcript": (turn.transcript or turn.committed).strip(),
                }
            )
            self._previous_item = item
            self._items.pop(order, None)
            self._sent.pop(order, None)


# ----------------------------------------------------------------------------------------
# Handler
# ----------------------------------------------------------------------------------------
async def realtime(request: web.Request) -> web.WebSocketResponse:
    """
    ``WS /v1/realtime?intent=transcription[&source=…][&model=…]``.

    Parameters
    ----------
    request: aiohttp.web.Request

    Returns
    -------
    ws: aiohttp.web.WebSocketResponse
    """
    protocols = [
        p.strip()
        for p in request.headers.get("Sec-WebSocket-Protocol", "").split(",")
        if p.strip()
    ]
    ws = web.WebSocketResponse(
        protocols=protocols[:1], heartbeat=20, max_msg_size=16 * 1024**2
    )
    await ws.prepare(request)
    intent = request.query.get("intent")
    source = request.query.get("source")
    session = TranscriptionSession(ws, request.app, source)
    if intent != "transcription":
        await session.error(
            "only transcription sessions are served (connect with ?intent=transcription)",
            "unsupported_intent",
        )
        await ws.close()
        return ws
    if source is not None and source not in _CAPTURE_SOURCES:
        await session.error(
            f"source must be one of {sorted(_CAPTURE_SOURCES)}", "invalid_value"
        )
        await ws.close()
        return ws
    lock: asyncio.Lock = request.app["realtime_lock"]
    if lock.locked():
        await session.error("another realtime session is running", "session_busy")
        await ws.close()
        return ws
    async with lock:
        session.model = request.query.get("model")
        await session.created()
        try:
            if source:
                await session.start()
            async for message in ws:
                if message.type != WSMsgType.TEXT:
                    continue
                event = json.loads(message.data)
                kind = event.get("type", "")
                if kind in ("session.update", "transcription_session.update"):
                    await session.update(event)
                elif kind == "input_audio_buffer.append":
                    await session.append(event)
                elif kind == "input_audio_buffer.commit":
                    await session.commit(event)
                elif kind == "input_audio_buffer.clear":
                    await session.send({"type": "input_audio_buffer.cleared"})
                else:
                    await session.error(
                        f"unsupported event {kind!r}",
                        "unknown_event",
                        event.get("event_id"),
                    )
        except SDKError as error:
            await session.error(error.message, error.code.lower())
        finally:
            await session.stop()
    return ws
