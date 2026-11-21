"""One prompt, tokens as they decode, then the metrics on the final chunk.

python examples/llm_stream.py "Write a haiku about the sea."
"""

import asyncio
import sys

from _common import initialize

import thestage_sdk as ts


async def main(prompt: str) -> None:
    await initialize()
    llm = await ts.TSLLM.load("TheStageAI/Qwen3-0.6B")
    print("defaults:", llm.generation_defaults)
    async for chunk in llm.infer_stream(
        prompt,
        system_prompt="Answer in plain text.",
        config={"enable_thinking": False, "max_new_tokens": 128},
    ):
        if chunk.is_final:
            print(
                f"\n{chunk.generated_tokens} tokens, "
                f"{chunk.tokens_per_second:.1f} tok/s, "
                f"first token {chunk.time_to_first_token:.2f} s, "
                f"stop: {chunk.stop_reason}"
            )
        else:
            print(chunk.text, end="", flush=True)


asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else "Write a haiku about the sea."))
