"""A language model's answer, spoken through the speakers while it is still being written.

pip install sounddevice
python examples/tts_play.py "Tell me about the Moon in three sentences."
"""

import asyncio
import sys

import sounddevice as sd
from _common import initialize

import thestage_sdk as ts


async def main(question: str) -> None:
    await initialize()
    llm = await ts.TSLLM.load("TheStageAI/Qwen3-0.6B", model_name="speak.llm")
    tts = await ts.TTSPipeline.load(
        "TheStageAI/neutts-nano-multilingual", voice_id="dave", language="english"
    )
    stream = await tts.open_stream()

    async def feed() -> None:
        async for chunk in llm.infer_stream(
            question,
            system_prompt="Answer in plain spoken sentences, no lists or markdown.",
            config={"enable_thinking": False, "max_new_tokens": 200},
        ):
            if not chunk.is_final:
                print(chunk.text, end="", flush=True)
                await stream.send(chunk.text)
        await stream.close()

    feeding = asyncio.create_task(feed())
    speakers = sd.OutputStream(samplerate=stream.sample_rate, channels=1, dtype="float32")
    with speakers as out:
        async for audio in stream:
            await asyncio.to_thread(out.write, audio)  # blocking write off the loop
    await feeding
    print()


asyncio.run(main(" ".join(sys.argv[1:]) or "Tell me about the Moon in three sentences."))
