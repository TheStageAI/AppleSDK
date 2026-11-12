"""Speak text: the whole clip in one call, and a stream fed sentence by sentence.

python examples/tts_speak.py "Hello from your Mac."
"""

import asyncio
import sys
import wave

import numpy as np
from _common import initialize

import thestage_sdk as ts


def save_wav(path: str, samples: np.ndarray, sample_rate: int) -> None:
    pcm = (np.clip(samples, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        w.writeframes(pcm.tobytes())


async def main(text: str) -> None:
    await initialize()
    tts = await ts.TTSPipeline.load(
        "TheStageAI/neutts-nano-multilingual", voice_id="dave", language="english"
    )
    result = await tts.infer(text, config={"temperature": 1.0, "top_k": 50, "seed": 7})
    save_wav("tts_full.wav", result.samples, result.sample_rate)
    print(f"tts_full.wav: {result.duration:.1f} s audio, {result.rtf:.1f}x real time")

    stream = await tts.open_stream()
    for sentence in ["This is a stream.", "Audio arrives while text is still coming."]:
        await stream.send(sentence)
    await stream.close()
    chunks = [chunk async for chunk in stream]
    save_wav("tts_stream.wav", np.concatenate(chunks), stream.sample_rate)
    print(f"tts_stream.wav: {len(chunks)} chunks")


asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else "Hello from your Mac."))
