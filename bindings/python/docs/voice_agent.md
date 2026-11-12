# Voice agent

[Docs home](README.md) · [Language models](llm.md) · [Vision](vlm.md) ·
[Speech recognition](asr.md) · [Microphone and audio](audio.md) · [Text to speech](tts.md) ·
[Server](server.md)

A spoken assistant on the Mac: it listens on the microphone, understands when you have
finished, answers with a language model, calls your tools, and speaks through the
speakers. You can interrupt it by talking. Nothing leaves the Mac.

## Start it

```python
import asyncio
import thestage_sdk as ts

await ts.initialize(api_token="your-api-token")
llm = await ts.TSLLM.load("TheStageAI/Qwen3-0.6B", model_name="agent.llm")

agent = await ts.TSVoiceAgent.create(
    ts.TSAgentConfig(
        stt="TheStageAI/thewhisper-large-v3-turbo",   # recogniser
        vad="TheStageAI/silero-vad",                  # voice activity detector
        turn_detector="TheStageAI/smart-turn-v3",     # answer when you sound finished
        language="auto",
        asr_streaming_config=ts.ASRStreamingConfig(algorithm="THESTAGE_V5_5"),
        audio=ts.TSAudioConfig(),       # microphone, platform echo canceller
    ),
    llm=llm,                                          # a loaded TSLLM
    tts="TheStageAI/neutts-nano-multilingual",        # speech model
    tts_voice="dave",                                 # "dave", "paul", "jo"
    system_prompt="You are a friendly voice assistant. Answer in one or two sentences.",
    tools=None,                                       # see Tools below
)

events = await agent.events()          # subscribe BEFORE start: events are not replayed
await agent.start()                    # microphone opens; a permission prompt may appear
await agent.say("Hi! What can I do for you?")

async for event in events:
    if event.kind == "user_request":
        print(f"\nyou: {event.data['text']}")
    elif event.kind == "response_delta":
        print(event.data["delta"], end="", flush=True)
```

Keep answers short in the system prompt: they are spoken, and a paragraph takes a while
to say.

## Controls

| Method | What it does |
|---|---|
| `start()` | Load what is needed, open the microphone and start listening |
| `stop()` | Stop the agent, unload its models, release the microphone and speakers |
| `pause_listening()` / `begin_listening()` | Close and reopen the microphone; models stay loaded (push-to-talk, a mute button) |
| `say(text)` | Speak this text as is, without the model (greetings, notifications) |
| `send_request(text)` | A typed request, answered like a spoken one (a chat box next to the voice) |
| `interrupt()` | Stop the current answer now and listen again (a stop button) |
| `clear_history()` | Forget the conversation |
| `set_system_prompt(prompt)` | Change the instructions for the next answers |

## Events

`TSAgentEvent`: `kind` and `data`.

| `kind` | `data` | When |
|---|---|---|
| `state_changed` | `state` | See the states below |
| `user_request_partial` | `text` | Live caption while you speak |
| `user_request` | `text`, `source` (`speech`, `text`, `system`) | Your request, final |
| `response_delta` | `delta` | The answer's next piece of text |
| `response_done` | `reason`, `interrupted` | The answer finished or was cut off |
| `playback_started`, `playback_ended` | `reason` on end | The speakers start and stop |
| `tool_started`, `tool_ended` | `name` | A tool call runs |
| `wake_word` | `prob` | A wake word was heard (when configured) |
| `error` | details | Something failed; the agent keeps running when it can |
| `metrics` | timings | Latency of a turn |

States (`state_changed`): `idle`, `loading`, `listening`, `thinking`, `tool_calling`,
`speaking`, and `sleeping` (waiting for a wake word).

A minimal UI loop:

```python
async for event in events:
    match event.kind:
        case "state_changed":
            status_bar.set(event.data["state"])            # "listening", "speaking", …
        case "user_request_partial":
            caption.set(event.data["text"])
        case "user_request":
            chat.add_user(event.data["text"])
        case "response_delta":
            chat.append_assistant(event.data["delta"])
        case "tool_started":
            chat.note(f"using {event.data['name']}…")
        case "error":
            log.warning("agent error: %s", event.data)
```

## Tools

The agent takes the same [`ts.Tool`](llm.md#tools) as a chat session. The model says a
short line while the tool runs ("Let me check."), your Python function runs, and the
agent speaks the answer.

```python
import datetime

async def set_timer(arguments: dict) -> dict:
    minutes = int(arguments["minutes"])
    asyncio.get_running_loop().call_later(
        minutes * 60, lambda: asyncio.create_task(agent.say("Your timer is done."))
    )
    return {"ok": True, "minutes": minutes}

def get_time(arguments: dict) -> str:
    return datetime.datetime.now().strftime("%H:%M")

agent = await ts.TSVoiceAgent.create(
    ts.TSAgentConfig(
        turn_detector="TheStageAI/smart-turn-v3",
        asr_streaming_config=ts.ASRStreamingConfig(algorithm="THESTAGE_V5_5"),
    ),
    llm=llm,
    tts="TheStageAI/neutts-nano-multilingual",
    tts_voice="dave",
    system_prompt="You are a kitchen assistant. Answer in one sentence.",
    tools=[
        ts.Tool(
            name="set_timer",
            description="Start a kitchen timer.",
            parameters={
                "type": "object",
                "properties": {"minutes": {"type": "integer", "minimum": 1}},
                "required": ["minutes"],
            },
            execute=set_timer,
        ),
        ts.Tool(
            name="get_time",
            description="The current local time.",
            parameters={"type": "object", "properties": {}},
            execute=get_time,
        ),
    ],
)
```

"Set a timer for ten minutes" → `tool_started {"name": "set_timer"}` → your function
runs → `tool_ended` → "Your ten-minute timer is running." The rules for `execute` are
the chat session's: `async` or plain (a plain function runs in a worker thread), a `str`
or JSON-able result, and an exception reaches the model as `{"error": …}` so it can say
the tool failed. Keep results short: they are read, then spoken about.

## Microphone, speakers and interruption

The agent listens on the **default microphone** and speaks through the **default
output**; choose both in System Settings → Sound. The microphone permission belongs to the
app that runs Python ([details](audio.md#permissions)).

You can talk over the agent: the echo canceller removes its own voice from the
microphone, so your voice stops the answer and becomes the next request. Settings in
`TSAgentConfig.audio` ([all of them](audio.md#tsaudioconfig)):

| Setup | Setting |
|---|---|
| MacBook speakers or headphones | Defaults |
| Compare cancellers on your hardware | `aec="vpio"` or `aec="neural"` |
| Speakers that echo too much to cancel | `mute_mic_during_playback=True` (no voice interruption while it speaks) |
| The first answer clips or echoes | `aec_warmup_ms=500` |
| Another playback rate | `sample_rate_out=48_000` |

Buttons work at any time: `interrupt()` stops the answer, `pause_listening()` closes the
microphone.

## Runnable example

- [`examples/voice_agent.py`](../examples/voice_agent.py): a spoken conversation with a local model and two tools (time, timer)
