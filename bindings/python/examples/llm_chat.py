"""Chat with memory: each reply streams as it decodes.

python examples/llm_chat.py
"""

import asyncio

from _common import initialize

import thestage_sdk as ts


async def main() -> None:
    await initialize()
    llm = await ts.TSLLM.load("TheStageAI/Qwen3-0.6B", model_name="chat", device="npu")
    session = ts.TSChatSession(
        llm,
        system_prompt="You are a helpful assistant. Answer briefly.",
        max_turns=8,
    )
    config = {"enable_thinking": False, "max_new_tokens": 256, "temperature": 0.7}
    while True:
        try:
            request = input("\nyou> ")
        except EOFError:
            break
        print("model> ", end="", flush=True)
        async for event in session.infer_stream(request, config=config):
            if event.kind == "text_delta":
                print(event.text, end="", flush=True)
            elif event.kind == "final":
                print(f"\n[{event.data.get('tokens_per_second', 0):.0f} tok/s]")


asyncio.run(main())
