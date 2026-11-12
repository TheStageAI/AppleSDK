"""The local server through the official ``openai`` client: chat, tools,
transcription and speech. Start the server first:

    thestage-sdk serve
    python examples/openai_client.py speech.m4a
"""

import asyncio
import sys
from pathlib import Path

from openai import AsyncOpenAI

client = AsyncOpenAI(base_url="http://127.0.0.1:8000/v1", api_key="local")


async def main(audio_path: str | None) -> None:
    # Chat, streamed. Any model name the server does not know maps to its --llm.
    stream = await client.chat.completions.create(
        model="TheStageAI/Qwen3-0.6B",
        messages=[{"role": "user", "content": "Name three uses of on-device AI."}],
        stream=True,
        max_tokens=120,
    )
    async for chunk in stream:
        print(chunk.choices[0].delta.content or "", end="", flush=True)
    print()

    # Speech, streamed to a file as it is generated (mp3 by default, like OpenAI).
    async with client.audio.speech.with_streaming_response.create(
        model="tts-1", voice="dave", input="Hello from your Mac.", response_format="wav"
    ) as response:
        await response.stream_to_file("hello.wav")
    print("wrote hello.wav")

    # Transcription with word timestamps: any file macOS can decode.
    result = await client.audio.transcriptions.create(
        model="whisper-1",
        file=Path(audio_path or "hello.wav"),
        response_format="verbose_json",
        timestamp_granularities=["word"],
    )
    print(f"[{result.language}] {result.text}")
    for word in result.words or []:
        print(f"  {word.start:6.2f}-{word.end:6.2f} {word.word}")


asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else None))
