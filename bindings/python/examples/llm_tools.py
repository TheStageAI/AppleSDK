"""A chat that calls Python tools: the SDK runs the tool loop, your functions run here.

python examples/llm_tools.py
python examples/llm_tools.py "What's the weather in Tokyo, and what time is it?"
"""

import asyncio
import datetime
import sys

from _common import initialize

import thestage_sdk as ts


async def get_weather(arguments: dict) -> dict:
    """A stand-in for a weather API: any async function works."""
    city = arguments["city"]
    return {"city": city, "temp_c": 17 + len(city) % 9, "sky": "cloudy"}


def get_time(arguments: dict) -> str:
    """A plain function runs in a worker thread."""
    return datetime.datetime.now().strftime("%H:%M")


TOOLS = [
    ts.Tool(
        name="get_weather",
        description="Current weather for a city. Use it for any weather question.",
        parameters={
            "type": "object",
            "properties": {"city": {"type": "string", "description": "City name"}},
            "required": ["city"],
        },
        execute=get_weather,
    ),
    ts.Tool(
        name="get_time",
        description="The current local time.",
        parameters={"type": "object", "properties": {}},
        execute=get_time,
    ),
]


async def ask(session: ts.TSChatSession, request: str) -> None:
    async for event in session.infer_stream(request, config={"enable_thinking": False}):
        if event.kind == "tool_call":
            print(f"\033[2m[{event.data['name']}({event.data['arguments']})]\033[0m")
        elif event.kind == "tool_result":
            print(f"\033[2m[→ {event.data['content']}]\033[0m")
        elif event.kind == "text_delta":
            print(event.text, end="", flush=True)
    print()


async def main() -> None:
    await initialize()
    llm = await ts.TSLLM.load("TheStageAI/Qwen3-0.6B", model_name="tools")
    async with ts.TSChatSession(
        llm, system_prompt="You are a helpful assistant.", tools=TOOLS
    ) as session:
        if len(sys.argv) > 1:
            await ask(session, " ".join(sys.argv[1:]))
            return
        while True:
            try:
                request = input("\nyou> ")
            except EOFError:
                break
            await ask(session, request)


asyncio.run(main())
