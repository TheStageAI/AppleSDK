# thestage_sdk for Python

TheStage's on-device AI on Apple Silicon Macs, from Python: language models with chat and
tools, vision, speech recognition (recordings and live), text to speech, a voice agent,
and an OpenAI-compatible local server. Models run natively at full speed; nothing leaves
the Mac.

| Page | What it covers |
|---|---|
| [Language models, chat and tools](llm.md) | `TSLLM`, `TSChatSession`, `ts.Tool`, generation settings, caller-run tools |
| [Vision-language models](vlm.md) | `TSVLM`: images by path, bytes or PIL |
| [Speech recognition](asr.md) | `ASRPipeline` for recordings, `ASREngine` for live turns |
| [Microphone and audio](audio.md) | Sources (microphone, system, meeting, push), permissions, echo cancellation, your own capture, playback |
| [Text to speech](tts.md) | `TTSPipeline`: whole clips and streaming text in, audio out |
| [Voice agent](voice_agent.md) | `TSVoiceAgent`: listening, answering, tools, interruption |
| [Local server](server.md) | `thestage-sdk serve`: the OpenAI API on these models, Open WebUI, Hermes |

## Install

From `bindings/python` in this repository:

```bash
pip install wheel
./scripts/build_wheel.sh              # once: builds and signs the native helper
pip install dist/thestage_sdk-*.whl
```

Add `aiohttp` and `lameenc` (`pip install aiohttp lameenc`) for the local
OpenAI-compatible server.

Requirements: macOS 15 or later on Apple Silicon, Python 3.10 or later, and a TheStage
API token. Building the wheel needs Xcode once; the wheel carries a signed native
helper that runs the models, so nothing else is needed where it is installed.

## First program

```python
import asyncio
import thestage_sdk as ts

async def main():
    await ts.initialize(api_token="your-api-token")
    llm = await ts.TSLLM.load("TheStageAI/Qwen3-0.6B")
    async with ts.TSChatSession(llm, system_prompt="Answer in one sentence.") as chat:
        async for event in chat.infer_stream("What can you do on a Mac?"):
            if event.kind == "text_delta":
                print(event.text, end="", flush=True)

asyncio.run(main())
```

## How the package works

**Async everywhere.** Every call is a coroutine; every stream is an `async for`
iterator. In a script, wrap the program in `asyncio.run(main())`. In Jupyter, `await`
directly in a cell.

**Initialize once.** `await ts.initialize(api_token=…, hf_token=None)` validates the
token; call it once per process before loading a model. `hf_token` is only for gated
Hugging Face repos. Keep the token out of code: `os.environ["THESTAGE_API_TOKEN"]`.

**Models are loaded by repo id** (`"TheStageAI/Qwen3-0.6B"`). The first load downloads
and prepares the model (minutes for large ones); later loads read the local copy. Each
model is loaded under a `model_name` (default: the repo id), and
`await ts.stop_model(model_name)` frees its memory. Load what you use, stop what you
don't: several large models at once can exhaust memory on 8 and 16 GB Macs.
`await ts.delete_model(repo_id)` removes a downloaded model from disk and returns a
`ModelDeletion` (`freed_bytes`, `revisions`); stop it first, or it raises `SDKError`
with code `ModelInUse` (`ModelBusy` while it is still downloading or loading).

**One process, one native helper.** The first call starts `thestage-host` in the
background; it exits with your process. All models live there, so two Python processes
load their models twice.

**Settings are plain values.** Generation settings are a `config` dict whose keys
override the model's defaults; audio and agent settings are dataclasses
(`TSAudioConfig`, `TSAgentConfig`) whose `None` fields keep the SDK's value.

**Audio** in is 1-D float32 mono (16 kHz for `ASRPipeline.infer`, any rate for
`ASREngine.push`); audio out is a float32 NumPy array at the model's `sample_rate`.
[Details](audio.md#audio-format).

**Errors** raise `ts.SDKError` with `code` and `message`:

| `code` | Meaning |
|---|---|
| `tokenValidationFailed` | The API token was refused or could not be checked (offline) |
| `UNKNOWN_HANDLE` | A model, session or stream used after it was stopped or closed |
| `INVALID_PARAM`, `MISSING_PARAM` | A call's argument is wrong or missing |
| `AUDIO_CAPTURE_PERMISSION_DENIED` | The terminal or IDE has no microphone or system audio permission |
| `AUDIO_CAPTURE_UNSUPPORTED` | System audio capture on macOS older than 14.2 |
| `HOST` | The native helper could not start or exited |

```python
try:
    llm = await ts.TSLLM.load("TheStageAI/does-not-exist")
except ts.SDKError as error:
    print(error.code, error.message)
```

## Examples

Runnable scripts in [`examples/`](../examples/). Each reads `THESTAGE_API_TOKEN` (and
`HF_TOKEN` when set) from the environment.

| Script | Shows |
|---|---|
| `llm_stream.py "prompt"` | Streamed tokens and the final metrics |
| `llm_chat.py` | A terminal chat with memory |
| `llm_tools.py` | A chat that calls Python tools |
| `vlm_describe.py photo.jpg` | Describe an image by path and by bytes |
| `asr_file.py speech.wav` | One-call transcription with word timestamps |
| `asr_engine_live.py [file.wav] [--source …] [--speakers]` | Live captions: microphone, system audio, both, or a pushed file |
| `mic_push.py [--device NAME]` | Live captions from a microphone you choose (sounddevice) |
| `tts_speak.py "text"` | A whole clip and a stream, to WAV files |
| `tts_play.py "question"` | A model's answer spoken through the speakers as it is written (sounddevice) |
| `voice_agent.py` | A spoken conversation with two tools (time, timer) |
| `openai_client.py [file]` | The local server through the official `openai` client |
| `realtime_transcribe.py [file.wav]` | Realtime transcription over the server's WebSocket |
| [`hermes/`](../examples/hermes/README.md) | Hermes Agent speaking and listening through the local server |
| [`open_webui/`](../examples/open_webui/README.md) | Open WebUI chatting, dictating and reading aloud on these models |

The API reference (every class and argument) is in the docstrings: `help(ts.TSChatSession)`.
