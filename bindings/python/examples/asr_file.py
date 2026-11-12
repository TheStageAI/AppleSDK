"""Transcribe a WAV file in one call, with word timestamps.

python examples/asr_file.py speech.wav
"""

import asyncio
import sys
import wave

import numpy as np
from _common import initialize

import thestage_sdk as ts


def load_wav_16k(path: str) -> np.ndarray:
    """16-bit PCM WAV → 16 kHz mono float32 (naive resample; use soundfile/librosa
    for production audio)."""
    with wave.open(path) as w:
        rate, channels = w.getframerate(), w.getnchannels()
        pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
    audio = pcm.reshape(-1, channels).mean(axis=1).astype(np.float32) / 32768
    if rate != 16_000:
        n = int(len(audio) * 16_000 / rate)
        audio = np.interp(np.linspace(0, len(audio) - 1, n), np.arange(len(audio)), audio)
    return audio.astype(np.float32)


async def main(path: str) -> None:
    await initialize()
    asr = await ts.ASRPipeline.load("TheStageAI/thewhisper-large-v3-turbo")
    result = await asr.infer(load_wav_16k(path), language="auto", timestamps="WORD")
    print(f"[{result.language}] {result.text}\n")
    for word in result.words:
        print(f"{word.t0:7.2f}–{word.t1:6.2f}  {word.text}")


asyncio.run(main(sys.argv[1]))
