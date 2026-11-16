"""Live transcription over the Realtime WebSocket: push a WAV at real time, or
let the server capture this Mac's microphone, system audio, or both.

    thestage-sdk serve
    python examples/realtime_transcribe.py speech.wav          # push a 16-bit WAV
    python examples/realtime_transcribe.py --source meeting    # server captures
"""

import argparse
import asyncio
import base64
import wave

import aiohttp

URL = "ws://127.0.0.1:8000/v1/realtime?intent=transcription"


async def push(ws: aiohttp.ClientWebSocketResponse, path: str) -> None:
    with wave.open(path) as w:
        assert w.getsampwidth() == 2 and w.getnchannels() == 1, "16-bit mono WAV"
        rate = w.getframerate()
        pcm = w.readframes(w.getnframes())
    await ws.send_json(
        {
            "type": "session.update",
            "session": {
                "type": "transcription",
                "audio": {"input": {"format": {"type": "audio/pcm", "rate": rate}}},
            },
        }
    )
    step = rate // 10 * 2  # 100 ms
    for i in range(0, len(pcm), step):
        audio = base64.b64encode(pcm[i : i + step]).decode()
        await ws.send_json({"type": "input_audio_buffer.append", "audio": audio})
        await asyncio.sleep(0.1)
    await ws.send_json({"type": "input_audio_buffer.commit"})  # the file ended


async def main(args: argparse.Namespace) -> None:
    url = URL + (f"&source={args.source}" if args.source else "")
    async with aiohttp.ClientSession() as session, session.ws_connect(url) as ws:
        sender = asyncio.create_task(push(ws, args.wav)) if args.wav else None
        async for message in ws:
            event = message.json()
            kind = event["type"]
            if kind == "thestage.transcription.partial":
                line = f"{event['committed']} \033[2m{event['hypothesis']}\033[0m"
                print("\r\033[K" + line, end="", flush=True)
            elif kind.endswith("transcription.completed"):
                print("\r\033[K" + event["transcript"])
                if sender and sender.done():
                    break
            elif kind == "error":
                print("error:", event["error"]["message"])
        if sender:
            await sender


parser = argparse.ArgumentParser()
parser.add_argument("wav", nargs="?", help="push this WAV instead of capturing")
parser.add_argument("--source", choices=["microphone", "system", "meeting"])
try:
    asyncio.run(main(parser.parse_args()))
except KeyboardInterrupt:
    pass
