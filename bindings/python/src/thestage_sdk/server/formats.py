"""Wire formats the OpenAI API uses: errors, PCM, WAV, SSE, subtitles."""

from __future__ import annotations

import json
import struct
from typing import ClassVar

import numpy as np
from aiohttp import web


# ----------------------------------------------------------------------------------------
# Errors
# ----------------------------------------------------------------------------------------
class OpenAIError(Exception):
    """
    An error in the OpenAI shape: ``{"error": {message, type, param, code}}``.

    Parameters
    ----------
    status: int
        HTTP status.
    message: str
    code: str, optional
        Machine-readable code, e.g. ``"model_not_found"``.
    param: str, optional
        The request field at fault.
    type: str
        ``"invalid_request_error"`` (default), ``"authentication_error"`` or
        ``"server_error"``.
    """

    # Constructor
    # ------------------------------------------------------------------------------------
    def __init__(
        self,
        status: int,
        message: str,
        code: str | None = None,
        param: str | None = None,
        type: str = "invalid_request_error",
    ):
        super().__init__(message)
        self.status = status
        self.body = {
            "error": {"message": message, "type": type, "param": param, "code": code}
        }

    # Public Methods
    # ------------------------------------------------------------------------------------
    def response(self) -> web.Response:
        """
        Returns
        -------
        response: aiohttp.web.Response
            The error as JSON with its status.
        """
        return web.json_response(self.body, status=self.status)


def bad_request(message: str, code: str | None = None, param: str | None = None):
    """
    A 400 ``invalid_request_error``.

    Parameters
    ----------
    message: str
    code: str, optional
    param: str, optional

    Returns
    -------
    error: OpenAIError
    """
    return OpenAIError(400, message, code=code, param=param)


# ----------------------------------------------------------------------------------------
# Audio
# ----------------------------------------------------------------------------------------
def s16le(samples: np.ndarray) -> bytes:
    """
    Parameters
    ----------
    samples: numpy.ndarray
        float32 in [-1, 1].

    Returns
    -------
    pcm: bytes
        16-bit little-endian, clipped.
    """
    return (np.clip(samples, -1.0, 1.0) * 32767.0).astype("<i2").tobytes()


def float32_from_s16le(data: bytes) -> np.ndarray:
    """
    Parameters
    ----------
    data: bytes
        16-bit little-endian PCM.

    Returns
    -------
    samples: numpy.ndarray
        float32 in [-1, 1).
    """
    return np.frombuffer(data, dtype="<i2").astype(np.float32) / 32768.0


def wav_header(sample_rate: int, data_bytes: int | None = None) -> bytes:
    """
    A mono 16-bit WAV header.

    Parameters
    ----------
    sample_rate: int
    data_bytes: int, optional
        Size of the PCM that follows. ``None`` streams: the sizes say "unknown"
        (0xFFFFFFFF), which players read to the end of the body.

    Returns
    -------
    header: bytes
        44 bytes.
    """
    size = 0xFFFFFFFF if data_bytes is None else data_bytes
    riff = 0xFFFFFFFF if data_bytes is None else 36 + data_bytes
    return struct.pack(
        "<4sI4s4sIHHIIHH4sI",
        b"RIFF", riff, b"WAVE", b"fmt ", 16, 1, 1,
        sample_rate, sample_rate * 2, 2, 16, b"data", size,
    )  # fmt: skip


class AudioWriter:
    """
    Speech in one of the formats ``/v1/audio/speech`` serves, chunk by chunk:
    ``start()``, then ``write(samples)`` per chunk, then ``end()``. Every format
    streams: WAV with an open-ended header, MP3 frames as they are encoded.

    Parameters
    ----------
    response_format: str
        ``"mp3"``, ``"wav"`` or ``"pcm"``.
    sample_rate: int
        The rate of the samples written.

    Raises
    ------
    OpenAIError
        Another format, or mp3 without ``lameenc`` installed.
    """

    CONTENT_TYPES: ClassVar[dict[str, str]] = {
        "mp3": "audio/mpeg",
        "wav": "audio/wav",
        "pcm": "audio/pcm",
    }

    # Constructor
    # ------------------------------------------------------------------------------------
    def __init__(self, response_format: str, sample_rate: int):
        self.check(response_format)
        self.format = response_format
        self.sample_rate = sample_rate
        self.content_type = self.CONTENT_TYPES[response_format]
        self._mp3 = self._mp3_encoder(sample_rate) if response_format == "mp3" else None

    # Public Methods
    # ------------------------------------------------------------------------------------
    @classmethod
    def check(cls, response_format: str) -> None:
        """
        Refuse a format before any work is done.

        Parameters
        ----------
        response_format: str

        Raises
        ------
        OpenAIError
            ``unsupported_response_format``.
        """
        if response_format not in cls.CONTENT_TYPES:
            raise bad_request(
                f"response_format {response_format!r} is not supported; "
                "use mp3, wav or pcm",
                code="unsupported_response_format",
                param="response_format",
            )

    def start(self) -> bytes:
        """
        Returns
        -------
        data: bytes
            The WAV header, or nothing for the other formats.
        """
        return wav_header(self.sample_rate) if self.format == "wav" else b""

    def write(self, samples: np.ndarray) -> bytes:
        """
        Parameters
        ----------
        samples: numpy.ndarray
            float32 mono at ``sample_rate``.

        Returns
        -------
        data: bytes
            PCM, or the MP3 frames ready so far.
        """
        pcm = s16le(samples)
        return bytes(self._mp3.encode(pcm)) if self._mp3 else pcm

    def end(self) -> bytes:
        """
        Returns
        -------
        data: bytes
            The MP3 encoder's last frames, or nothing.
        """
        return bytes(self._mp3.flush()) if self._mp3 else b""

    # Private Methods
    # ------------------------------------------------------------------------------------
    @staticmethod
    def _mp3_encoder(sample_rate: int):
        """
        Parameters
        ----------
        sample_rate: int

        Returns
        -------
        encoder: lameenc.Encoder
            Mono, 64 kbit/s.
        """
        try:
            import lameenc
        except ImportError:
            raise OpenAIError(
                400,
                "mp3 needs the server extra: pip install 'thestage_sdk[server]'",
                code="unsupported_response_format",
                param="response_format",
            ) from None
        encoder = lameenc.Encoder()
        encoder.set_bit_rate(64)
        encoder.set_in_sample_rate(sample_rate)
        encoder.set_channels(1)
        encoder.set_quality(2)
        return encoder


# ----------------------------------------------------------------------------------------
# Server-sent events
# ----------------------------------------------------------------------------------------
# The request key that holds a response whose headers were already sent.
SSE_RESPONSE = "thestage.sse_response"
STREAM_RESPONSE = "thestage.stream_response"


async def sse_response(request: web.Request) -> web.StreamResponse:
    """
    Start a server-sent events response.

    Parameters
    ----------
    request: aiohttp.web.Request

    Returns
    -------
    response: aiohttp.web.StreamResponse
    """
    response = web.StreamResponse(
        headers={
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        }
    )
    await response.prepare(request)
    # Headers are sent: a later error goes in-band (``sse_error``), not as a status.
    request[SSE_RESPONSE] = response
    return response


async def sse_error(response: web.StreamResponse, error: OpenAIError) -> None:
    """
    End a started SSE response with an OpenAI ``error`` event, then ``[DONE]``.

    Parameters
    ----------
    response: aiohttp.web.StreamResponse
        A response ``sse_response`` started.
    error: OpenAIError
    """
    try:
        await sse_send(response, error.body)
        await sse_send(response, "[DONE]")
    except (ConnectionResetError, RuntimeError):
        pass  # the client already left


async def sse_send(response: web.StreamResponse, data: dict | str) -> None:
    """
    Send one ``data:`` event.

    Parameters
    ----------
    response: aiohttp.web.StreamResponse
    data: dict or str
        JSON-encoded unless a string (``"[DONE]"``).
    """
    payload = data if isinstance(data, str) else json.dumps(data, ensure_ascii=False)
    await response.write(f"data: {payload}\n\n".encode())


# ----------------------------------------------------------------------------------------
# Subtitles
# ----------------------------------------------------------------------------------------
def segments(words: list, max_s: float = 12.0) -> list[dict]:
    """
    Words into sentence-like segments.

    Parameters
    ----------
    words: list of ASRWord
    max_s: float
        A segment ends after ``.``, ``?`` or ``!``, or before it would pass this
        many seconds. Default is 12.

    Returns
    -------
    segments: list of dict
        OpenAI's ``verbose_json`` segments: ``id``, ``start``, ``end``, ``text``
        and zeroed decoder statistics.
    """
    out, current = [], []
    for word in words:
        if current and word.t1 - current[0].t0 > max_s:
            out.append(current)
            current = []
        current.append(word)
        if word.text.rstrip().endswith((".", "?", "!", "。", "？", "！")):
            out.append(current)
            current = []
    if current:
        out.append(current)
    return [
        {
            "id": i,
            "seek": 0,
            "start": round(seg[0].t0, 3),
            "end": round(seg[-1].t1, 3),
            "text": " ".join(w.text.strip() for w in seg),
            "tokens": [],
            "temperature": 0.0,
            "avg_logprob": 0.0,
            "compression_ratio": 0.0,
            "no_speech_prob": 0.0,
        }
        for i, seg in enumerate(out)
    ]


def _clock(seconds: float, separator: str) -> str:
    """
    Parameters
    ----------
    seconds: float
    separator: str
        ``","`` for SRT, ``"."`` for WebVTT.

    Returns
    -------
    clock: str
        ``HH:MM:SS<sep>mmm``.
    """
    ms = round(seconds * 1000)
    h, ms = divmod(ms, 3_600_000)
    m, ms = divmod(ms, 60_000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d}{separator}{ms:03d}"


def srt(segs: list[dict]) -> str:
    """
    Parameters
    ----------
    segs: list of dict
        From ``segments``.

    Returns
    -------
    text: str
        SubRip subtitles.
    """
    return "\n".join(
        f"{i + 1}\n{_clock(s['start'], ',')} --> {_clock(s['end'], ',')}\n{s['text']}\n"
        for i, s in enumerate(segs)
    )


def vtt(segs: list[dict]) -> str:
    """
    Parameters
    ----------
    segs: list of dict
        From ``segments``.

    Returns
    -------
    text: str
        WebVTT subtitles.
    """
    body = "\n".join(
        f"{_clock(s['start'], '.')} --> {_clock(s['end'], '.')}\n{s['text']}\n"
        for s in segs
    )
    return "WEBVTT\n\n" + body
