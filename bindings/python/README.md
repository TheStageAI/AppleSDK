# thestage_sdk

TheStage's on-device AI SDK for Python on Apple Silicon Macs: language models with chat
sessions and Python tools, vision-language models, speech recognition (recordings and
live), text to speech, the voice agent, and an OpenAI-compatible local server. Models run
natively in a signed helper that ships inside the wheel, so speed is the native speed.

- Requirements: macOS 15 or later, Apple Silicon, Python 3.10 or later.
- Everything is `async`. Streams are `async for` iterators.

Build the wheel from this folder (Xcode 16 or later, once), then install it:

```bash
pip install wheel
./scripts/build_wheel.sh              # once: builds and signs the native helper
pip install dist/thestage_sdk-*.whl
```

```python
import asyncio
import thestage_sdk as ts

async def get_weather(arguments: dict) -> dict:
    return {"city": arguments["city"], "temp_c": 17, "sky": "cloudy"}

async def main():
    await ts.initialize(api_token="your-api-token")
    llm = await ts.TSLLM.load("TheStageAI/Qwen3-0.6B")
    weather = ts.Tool(
        name="get_weather",
        description="Current weather for a city.",
        parameters={"type": "object", "properties": {"city": {"type": "string"}},
                    "required": ["city"]},
        execute=get_weather,
    )
    async with ts.TSChatSession(llm, tools=[weather]) as chat:
        async for event in chat.infer_stream("What's the weather in Paris?",
                                             config={"enable_thinking": False}):
            if event.kind == "text_delta":
                print(event.text, end="", flush=True)

asyncio.run(main())
```

## Documentation

| Page | What it covers |
|---|---|
| [Overview](docs/README.md) | Install, how the package works, errors, all examples |
| [Language models, chat and tools](docs/llm.md) | `TSLLM`, `TSChatSession`, `ts.Tool`, generation settings, caller-run tools |
| [Vision-language models](docs/vlm.md) | `TSVLM`: images by path, bytes or PIL |
| [Speech recognition](docs/asr.md) | `ASRPipeline` for recordings, `ASREngine` for live turns |
| [Microphone and audio](docs/audio.md) | Microphone, system audio, meetings, your own capture, permissions, echo cancellation, playback |
| [Text to speech](docs/tts.md) | `TTSPipeline`: whole clips and streaming |
| [Voice agent](docs/voice_agent.md) | `TSVoiceAgent`: listening, answering, tools, interruption |
| [Local server](docs/server.md) | `thestage-sdk serve`: the OpenAI API, Open WebUI, Hermes |

Runnable scripts for each are in [`examples/`](examples/).

