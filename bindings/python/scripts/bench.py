"""Speed through the Python bindings against the SDK's own numbers.

LLM: tokens per second the SDK reports for its decode, against tokens per
second Python receives (first chunk to last). TTS: the SDK's speed
(× real time) against audio seconds per wall second as Python receives them. The gate
in the plan is within 2 %.

    THESTAGE_HOST_BIN=… THESTAGE_API_TOKEN=… python3 scripts/bench.py
"""

import asyncio
import os
import time

import thestage_sdk as ts

LLM = os.environ.get("BENCH_LLM", "TheStageAI/Qwen3-0.6B")
TTS = os.environ.get("BENCH_TTS", "TheStageAI/neutts-nano-multilingual")
PROMPT = "Write a short paragraph about the sea, about eighty words."


async def bench_llm(runs: int = 3) -> None:
    llm = await ts.TSLLM.load(LLM)
    config = {"enable_thinking": False, "max_new_tokens": 128}
    for run in range(runs):
        first = last = None
        tokens = 0
        reported = None
        async for chunk in llm.infer_stream(PROMPT, config=config):
            now = time.perf_counter()
            if chunk.is_final:
                reported = chunk.tokens_per_second
                break
            tokens += 1
            first = first or now
            last = now
        seen = (
            (tokens - 1) / (last - first) if tokens > 1 and last > first else float("nan")
        )
        loss = 100 * (1 - seen / reported) if reported else float("nan")
        print(
            f"llm run {run}: sdk {reported:.1f} tok/s, python {seen:.1f} tok/s "
            f"({loss:+.1f} % slower)"
        )


async def bench_tts(runs: int = 3) -> None:
    tts = await ts.TTSPipeline.load(TTS, voice_id=os.environ.get("BENCH_VOICE"))
    text = "The quick brown fox jumps over the lazy dog. " * 3
    for run in range(runs):
        start = time.perf_counter()
        result = await tts.infer(text)
        wall = time.perf_counter() - start
        # `rtf` is "× real time" (audio seconds per compute second).
        python_x = result.duration / wall
        print(
            f"tts run {run}: sdk {result.rtf:.2f}x real time, python {python_x:.2f}x "
            f"({100 * (1 - python_x / result.rtf):+.1f} % slower), "
            f"{len(result.samples)} samples"
        )


async def main() -> None:
    await ts.initialize(
        api_token=os.environ["THESTAGE_API_TOKEN"],
        hf_token=os.environ.get("HF_TOKEN"),
    )
    await bench_llm()
    await bench_tts()


if __name__ == "__main__":
    asyncio.run(main())
