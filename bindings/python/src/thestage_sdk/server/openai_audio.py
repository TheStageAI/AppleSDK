"""``/v1/audio/transcriptions`` and ``/v1/audio/speech``.

Transcription decodes the upload natively (AVAudioFile formats) and runs the
SDK's batch path with VAD cuts; ``stream=true`` sends the transcript as it
settles (SSE ``transcript.text.delta``, then ``transcript.text.done``). Speech
streams audio as the model makes it, as the body itself (``wav``, ``pcm``) or
as SSE ``speech.audio.delta`` events.
"""

from __future__ import annotations

import base64
import logging
from pathlib import PurePath

from aiohttp import web

from .._host import SDKError
from ..audio import decode_audio
from . import formats
from .formats import bad_request, sse_response, sse_send
from .registry import OPENAI_VOICES, ModelRegistry

log = logging.getLogger("thestage_sdk.server")

# Containers AVAudioFile cannot read; named in the error instead of a decode failure.
_UNREADABLE = {"webm", "ogg", "oga", "opus", "mkv"}


# ----------------------------------------------------------------------------------------
# Routes
# ----------------------------------------------------------------------------------------
def setup(app: web.Application) -> None:
    """
    Register ``/v1/audio/transcriptions`` and ``/v1/audio/speech``.

    Parameters
    ----------
    app: aiohttp.web.Application
    """
    app["voices"] = {}
    app.router.add_post("/v1/audio/transcriptions", transcriptions)
    app.router.add_post("/v1/audio/speech", speech)


# ----------------------------------------------------------------------------------------
# Transcription
# ----------------------------------------------------------------------------------------
async def _form(request: web.Request) -> tuple[dict, bytes, str]:
    """
    Parameters
    ----------
    request: aiohttp.web.Request
        A multipart upload.

    Returns
    -------
    fields: dict
        The form's other fields; ``name[]`` fields as lists.
    data: bytes
        The file.
    filename: str

    Raises
    ------
    OpenAIError
        No file.
    """
    fields, data, filename = {}, b"", ""
    reader = await request.multipart()
    async for part in reader:
        if part.name == "file":
            filename = part.filename or ""
            data = await part.read()
        elif part.name.endswith("[]"):
            fields.setdefault(part.name[:-2], []).append(await part.text())
        else:
            fields[part.name] = await part.text()
    if not data:
        raise bad_request("file is required", param="file")
    return fields, data, filename


async def transcriptions(request: web.Request) -> web.StreamResponse:
    """
    ``POST /v1/audio/transcriptions``.

    Parameters
    ----------
    request: aiohttp.web.Request

    Returns
    -------
    response: aiohttp.web.StreamResponse
    """
    fields, data, filename = await _form(request)
    ext = PurePath(filename).suffix.lstrip(".").lower() or None
    if ext in _UNREADABLE:
        raise bad_request(
            f".{ext} is not supported; send wav, m4a, mp3, flac, aac, caf or aiff",
            code="unsupported_audio_format",
            param="file",
        )
    try:
        audio = await decode_audio(data, sample_rate=16_000, format=ext)
    except SDKError as error:
        raise bad_request(
            error.message, code="unsupported_audio_format", param="file"
        ) from None
    registry: ModelRegistry = request.app["registry"]
    asr = await registry.get("asr", fields.get("model"))
    language = fields.get("language") or "auto"
    response_format = fields.get("response_format", "json")
    stream = fields.get("stream", "false").lower() == "true"
    async with registry.lock(asr):
        if stream:
            return await _transcription_stream(request, asr, audio, language)
        result = await asr.infer(audio, language=language, timestamps="WORD")
    return _transcription_response(result, response_format, len(audio) / 16_000, fields)


def _transcription_response(result, response_format: str, duration: float, fields: dict):
    """
    Parameters
    ----------
    result: ASRResult
    response_format: str
        ``json``, ``text``, ``verbose_json``, ``srt`` or ``vtt``.
    duration: float
        The audio's length in seconds.
    fields: dict
        The request's form fields.

    Returns
    -------
    response: aiohttp.web.Response
    """
    text = result.text.strip()
    if response_format == "text":
        return web.Response(text=text)
    if response_format in ("srt", "vtt"):
        segs = formats.segments(result.words)
        body = formats.srt(segs) if response_format == "srt" else formats.vtt(segs)
        return web.Response(text=body)
    if response_format == "verbose_json":
        granularities = fields.get("timestamp_granularities") or ["segment"]
        out = {
            "task": "transcribe",
            "language": result.language or fields.get("language") or "",
            "duration": round(duration, 3),
            "text": text,
            "segments": formats.segments(result.words),
        }
        if "word" in granularities:
            out["words"] = [
                {"word": w.text.strip(), "start": round(w.t0, 3), "end": round(w.t1, 3)}
                for w in result.words
            ]
        return web.json_response(out)
    if response_format == "json":
        return web.json_response({"text": text})
    raise bad_request(
        f"response_format {response_format!r}: use json, text, verbose_json, srt or vtt",
        param="response_format",
    )


async def _transcription_stream(request, asr, audio, language) -> web.StreamResponse:
    """
    SSE ``transcript.text.delta`` as the text settles, then
    ``transcript.text.done``.

    Parameters
    ----------
    request: aiohttp.web.Request
    asr: ASRPipeline
    audio: numpy.ndarray
    language: str

    Returns
    -------
    response: aiohttp.web.StreamResponse
    """
    response = await sse_response(request)
    sent = ""
    async for result, is_final in asr.infer_stream(
        audio, language=language, timestamps="WORD"
    ):
        text = result.text.strip()
        if is_final:
            if text.startswith(sent) and len(text) > len(sent):
                delta = text[len(sent) :]
                await sse_send(
                    response, {"type": "transcript.text.delta", "delta": delta}
                )
            await sse_send(response, {"type": "transcript.text.done", "text": text})
        elif len(text) > len(sent):
            delta = text[len(sent) :]
            sent = text
            await sse_send(response, {"type": "transcript.text.delta", "delta": delta})
    return response


# ----------------------------------------------------------------------------------------
# Speech
# ----------------------------------------------------------------------------------------
async def use_voice(app: web.Application, tts, voice: str | None) -> None:
    """
    Switch ``tts`` to ``voice`` when it is one of the model's voices; OpenAI's
    voice names and unknown voices keep the configured voice.

    Parameters
    ----------
    app: aiohttp.web.Application
    tts: TTSPipeline
    voice: str or None
    """
    config = app["config"]
    wanted = voice if voice and voice.lower() not in OPENAI_VOICES else config.voice
    current = app["voices"].get(id(tts), config.voice)
    if not wanted or wanted == current:
        return
    try:
        await tts.set_voice(wanted, language=config.tts_language)
        app["voices"][id(tts)] = wanted
    except SDKError:
        if current != config.voice and config.voice:
            await tts.set_voice(config.voice, language=config.tts_language)
            app["voices"][id(tts)] = config.voice


async def speech(request: web.Request) -> web.StreamResponse:
    """
    ``POST /v1/audio/speech``: audio streamed as it is made.

    Parameters
    ----------
    request: aiohttp.web.Request

    Returns
    -------
    response: aiohttp.web.StreamResponse
    """
    body = await request.json()
    log.debug("speech request: %s", body)
    text = body.get("input") or ""
    if not text.strip():
        raise bad_request("input is required", param="input")

    response_format = body.get("response_format") or "mp3"
    formats.AudioWriter.check(response_format)
    sse = body.get("stream_format") == "sse"
    registry: ModelRegistry = request.app["registry"]
    tts = await registry.get("tts", body.get("model"))
    async with registry.lock(tts):
        await use_voice(request.app, tts, body.get("voice"))
        stream = await tts.open_stream()
        await stream.send(text)
        await stream.close()
        writer = formats.AudioWriter(response_format, stream.sample_rate)
        if sse:
            response = await sse_response(request)
        else:
            response = web.StreamResponse(
                headers={
                    "Content-Type": writer.content_type,
                    "X-Audio-Sample-Rate": str(stream.sample_rate),
                }
            )
            await response.prepare(request)
            request[formats.STREAM_RESPONSE] = response

        async def emit(data: bytes) -> None:
            if not data:
                return
            if sse:
                audio = base64.b64encode(data).decode()
                await sse_send(response, {"type": "speech.audio.delta", "audio": audio})
            else:
                await response.write(data)

        try:
            await emit(writer.start())
            async for chunk in stream:
                await emit(writer.write(chunk))
            await emit(writer.end())
            if sse:
                await sse_send(response, {"type": "speech.audio.done", "usage": {}})
        except ConnectionResetError:
            await stream.cancel()
            async for _ in stream:
                pass
    return response
