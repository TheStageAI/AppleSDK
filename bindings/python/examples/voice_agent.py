"""Talk to a local assistant: microphone in, speakers out, tools in Python, all on device.

python examples/voice_agent.py      # Ctrl-C to stop

Try: "What time is it?" or "Set a timer for one minute." Talk over it to interrupt.
"""

import asyncio
import datetime

from _common import initialize

import thestage_sdk as ts


def get_time(arguments: dict) -> str:
    return datetime.datetime.now().strftime("%H:%M")


async def main() -> None:
    await initialize()
    llm = await ts.TSLLM.load("TheStageAI/Qwen3-0.6B", model_name="agent.llm")
    agent: ts.TSVoiceAgent | None = None

    async def set_timer(arguments: dict) -> dict:
        minutes = max(1, int(arguments.get("minutes", 1)))

        async def ring() -> None:
            await asyncio.sleep(minutes * 60)
            await agent.say(f"Your {minutes} minute timer is done.")

        asyncio.create_task(ring())
        return {"ok": True, "minutes": minutes}

    agent = await ts.TSVoiceAgent.create(
        ts.TSAgentConfig(
            stt="TheStageAI/thewhisper-large-v3-turbo",
            turn_detector="TheStageAI/smart-turn-v3",
            asr_streaming_config=ts.ASRStreamingConfig(algorithm="THESTAGE_V5_5"),
        ),
        llm=llm,
        tts="TheStageAI/neutts-nano-multilingual",
        tts_voice="dave",
        system_prompt="You are a friendly voice assistant. Answer in one or two "
        "sentences.",
        tools=[
            ts.Tool(
                name="get_time",
                description="The current local time.",
                parameters={"type": "object", "properties": {}},
                execute=get_time,
            ),
            ts.Tool(
                name="set_timer",
                description="Start a timer that rings after some minutes.",
                parameters={
                    "type": "object",
                    "properties": {"minutes": {"type": "integer", "minimum": 1}},
                    "required": ["minutes"],
                },
                execute=set_timer,
            ),
        ],
    )
    events = await agent.events()  # subscribe before start
    await agent.start()
    await agent.say("Hi! What can I do for you?")
    async for event in events:
        if event.kind == "user_request":
            print(f"\nyou: {event.data.get('text', '')}")
        elif event.kind == "response_delta":
            print(event.data.get("delta", ""), end="", flush=True)
        elif event.kind == "tool_started":
            print(f"\n[{event.data.get('name')}…]", end="", flush=True)
        elif event.kind == "state_changed":
            print(f"\n[{event.data.get('state')}]", end="", flush=True)


try:
    asyncio.run(main())
except KeyboardInterrupt:
    pass
