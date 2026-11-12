"""``WS /v1/audio/speech/stream``: text in as it arrives, speech out as it is
made (TheStage extension; OpenAI has no text-streaming speech endpoint).

Query: ``model``, ``voice``, ``format`` (``pcm``: binary s16le frames at the
model's rate, the default; ``wav``: the same after a streaming WAV header;
``mp3``: MPEG frames as they are encoded).
Client: ``{"type": "text", "text": "…"}`` any number of times, then
``{"type": "close"}`` (speak what is left) or ``{"type": "cancel"}``.
Server: ``{"type": "session.created", "sample_rate"}``, binary audio frames,
``{"type": "done", "duration"}``.
"""

from __future__ import annotations

import asyncio
import json

from aiohttp import WSMsgType, web

from .._host import SDKError
from . import formats
from .formats import OpenAIError
from .openai_audio import use_voice
from .registry import ModelRegistry


# ----------------------------------------------------------------------------------------
# Routes
# ----------------------------------------------------------------------------------------
def setup(app: web.Application) -> None:
    """
    Register ``/v1/audio/speech/stream``.

    Parameters
    ----------
    app: aiohttp.web.Application
    """
    app.router.add_get("/v1/audio/speech/stream", speech_stream)


# ----------------------------------------------------------------------------------------
# Handler
# ----------------------------------------------------------------------------------------
async def speech_stream(request: web.Request) -> web.WebSocketResponse:
    """
    ``WS /v1/audio/speech/stream?voice=…&format=…&model=…``.

    Parameters
    ----------
    request: aiohttp.web.Request

    Returns
    -------
    ws: aiohttp.web.WebSocketResponse
    """
    ws = web.WebSocketResponse(heartbeat=20)
    await ws.prepare(request)
    audio_format = request.query.get("format", "pcm")
    registry: ModelRegistry = request.app["registry"]
    try:
        formats.AudioWriter.check(audio_format)
        tts = await registry.get("tts", request.query.get("model"))
    except OpenAIError as error:  # the socket is open: report in-band
        await ws.send_json({"type": "error", "error": error.body["error"]})
        await ws.close()
        return ws
    except SDKError as error:
        await ws.send_json(
            {
                "type": "error",
                "error": {"code": error.code.lower(), "message": error.message},
            }
        )
        await ws.close()
        return ws
    async with registry.lock(tts):
        await use_voice(request.app, tts, request.query.get("voice"))
        stream = await tts.open_stream()
        writer = formats.AudioWriter(audio_format, stream.sample_rate)
        await ws.send_json({"type": "session.created", "sample_rate": stream.sample_rate})

        async def send(data: bytes) -> None:
            if data and not ws.closed:
                await ws.send_bytes(data)

        async def pump() -> int:
            samples = 0
            await send(writer.start())
            async for chunk in stream:
                samples += len(chunk)
                await send(writer.write(chunk))
            await send(writer.end())
            return samples

        audio = asyncio.create_task(pump())
        closed = False
        try:
            async for message in ws:
                if message.type != WSMsgType.TEXT:
                    continue
                event = json.loads(message.data)
                kind = event.get("type")
                if kind == "text":
                    await stream.send(event.get("text", ""))
                elif kind == "close":
                    await stream.close()
                    closed = True
                    break
                elif kind == "cancel":
                    await stream.cancel()
                    closed = True
                    break
            if not closed:  # the client went away
                await stream.cancel()
            samples = await audio
            if not ws.closed:
                await ws.send_json(
                    {"type": "done", "duration": samples / stream.sample_rate}
                )
                await ws.close()
        except SDKError as error:
            if not ws.closed:
                await ws.send_json(
                    {
                        "type": "error",
                        "error": {"code": error.code.lower(), "message": error.message},
                    }
                )
                await ws.close()
            audio.cancel()
    return ws
