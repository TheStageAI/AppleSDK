"""Describe an image (a path, encoded bytes or a PIL image).

python examples/vlm_describe.py photo.jpg
"""

import asyncio
import sys
from pathlib import Path

from _common import initialize

import thestage_sdk as ts


async def main(image: str) -> None:
    await initialize()
    vlm = await ts.TSVLM.load("TheStageAI/LFM2.5-VL-450M")

    async for chunk in vlm.infer_stream(
        [image],
        "Describe this image in two sentences.",
        config={"max_new_tokens": 128},
    ):
        if not chunk.is_final:
            print(chunk.text, end="", flush=True)
    print()

    encoded = Path(image).read_bytes()  # bytes work as well as paths
    result = await vlm.infer([encoded], "What is the main object? One word.")
    print("main object:", result.text.strip())


asyncio.run(main(sys.argv[1]))
