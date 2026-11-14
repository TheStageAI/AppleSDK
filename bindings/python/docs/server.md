# Local OpenAI-compatible server

[Docs home](README.md) · [Language models](llm.md) · [Vision](vlm.md) ·
[Speech recognition](asr.md) · [Microphone and audio](audio.md) · [Text to speech](tts.md) ·
[Voice agent](voice_agent.md)

`thestage-sdk serve` runs TheStage models on this Mac behind the OpenAI API. Anything that
can point at an OpenAI-compatible base URL uses them with no code changes: the official
`openai` client, Open WebUI, Hermes Agent, LibreChat, Pipecat, LiveKit Agents, LangChain.
Models run natively in `thestage-host`; the server only translates requests.

```bash
pip install aiohttp lameenc      # server extras
export THESTAGE_API_TOKEN=…
thestage-sdk serve
# thestage-sdk: OpenAI-compatible API at http://127.0.0.1:8000/v1
```

```python
from openai import OpenAI
client = OpenAI(base_url="http://127.0.0.1:8000/v1", api_key="local")
```

## Contents

- [Command line](#command-line)
- [Models and names](#models-and-names)
- [Chat completions](#chat-completions)
- [Transcriptions](#transcriptions)
- [Speech](#speech)
- [Realtime transcription (WebSocket)](#realtime-transcription-websocket)
- [Speech from streaming text (WebSocket)](#speech-from-streaming-text-websocket)
- [Errors](#errors)
- [Integrations](#integrations)
- [Differences from OpenAI](#differences-from-openai)

## Command line

```bash
thestage-sdk serve \
    --llm TheStageAI/Qwen3-0.6B,TheStageAI/LFM2.5-350M \  # chat models (first = default); "all"; "none"
    --vlm TheStageAI/LFM2.5-VL-450M \           # vision model for messages with images
    --asr TheStageAI/thewhisper-large-v3-turbo \
    --tts TheStageAI/neutts-nano-multilingual \
    --voice dave --tts-language english \       # default voice (NeuTTS: paul, dave, jo)
    --vad TheStageAI/silero-vad \               # cuts files in silence; "none" = fixed cuts
    --aec webrtc \                              # canceller for sessions capturing the mic
    --streaming-algorithm THESTAGE_V5_5 \       # realtime commit policy; "pack" = the model's
    --turn-detector TheStageAI/smart-turn-v3 \  # realtime turn model; "none" (not with V5.5)
    --only-configured-models \                  # refuse other TheStageAI repos
    --host 127.0.0.1 --port 8000 \
    --api-key secret \                          # required off localhost; or THESTAGE_SERVER_API_KEY
    --api-token … \                             # or THESTAGE_API_TOKEN
    --preload                                   # load every model before serving
```

| Flag | Default |
|---|---|
| `--llm` | `TheStageAI/Qwen3-0.6B`. A comma-separated list offers several (the first is the default); `all` offers every shipped chat model |
| `--vlm` | none (image requests fail with `model_not_found`) |
| `--asr` | `TheStageAI/thewhisper-large-v3-turbo` |
| `--tts` | `TheStageAI/neutts-nano-multilingual`, voice `dave` |
| `--vad` | `TheStageAI/silero-vad` |
| `--host` / `--port` | `127.0.0.1` / `8000` |

Models load on first use unless `--preload` (which loads the default chat model). One
language model is loaded at a time: a request for another unloads the last once its
running request finishes, so switching in a model picker costs a load (seconds once
downloaded), not memory.

`--llm all` offers, default first: `TheStageAI/Qwen3-0.6B`, `TheStageAI/LFM2.5-230M`,
`TheStageAI/LFM2.5-350M`, `TheStageAI/gemma-3-1b-it`, `TheStageAI/LFM2.5-1.2B`,
`TheStageAI/gemma-4-E2B-it`. Their contexts are 1,256 to 2,048 tokens: enough for chat,
not for agents that send long system prompts and many tools.

**Speculative decoding.** A chat model whose pack ships a drafter (Gemma 4 E2B, LFM2.5
230M / 350M / 1.2B) is listed twice: `<repo>` and `<repo>:speculative`. The second is the
same loaded model decoding greedily with its drafter, several tokens per step; the
request's `temperature` and `top_p` are ignored, since the drafter runs on greedy
decoding only. Switching between the two loads nothing. Measured on an M2 Max through the
server (prose, 128 tokens): Gemma 4 E2B 38.9 → 50.4 tok/s with the same text; the LFM2.5
drafters gave no gain on this machine (181 → 182 tok/s on 350M). A host other than localhost needs
`--api-key`; requests then send `Authorization: Bearer <key>` (WebSockets may send the
subprotocol `openai-insecure-api-key.<key>` instead, as browsers cannot set headers).

`thestage-sdk transcribe FILE [--language en] [--url http://127.0.0.1:8000]` prints a
transcript: through the running server when there is one, otherwise by loading the model
itself. It is the command-provider hook for tools without a speech-to-text base URL.

## Models and names

`GET /v1/models` lists the language models, offered with `--llm` and loaded since: `{"id",
"object": "model", "owned_by": "thestage", "kind": "llm"}`. Clients such as Open WebUI
offer this list in their model picker. The vision model is not on it unless there is no
`--llm`: a message with an image reaches `--vlm` whichever chat model is picked, and on
text alone LFM2.5-VL mostly stops at once. A request naming `--vlm` still reaches it. The
speech models are not listed; the audio endpoints take their repo ids and OpenAI's names.
A chat request naming the server's speech model gets a 400.

A request's `model` picks the model:

| `model` | Served by |
|---|---|
| A `TheStageAI/…` repo id | That model, loaded on first use (unless `--only-configured-models`) |
| `whisper-1`, `gpt-4o-transcribe`, `gpt-4o-mini-transcribe` | `--asr` |
| `tts-1`, `tts-1-hd`, `gpt-4o-mini-tts` | `--tts` |
| Anything else (`gpt-4o`, `local`, empty) | The configured model of that kind |

One request runs per model at a time; others wait their turn. `GET /health` answers
`{"status": "ok"}` without auth.

## Chat completions

`POST /v1/chat/completions`

| Field | Meaning here |
|---|---|
| `messages` | `system` / `developer` (joined into one system prompt), `user` (text, or parts `text` and `image_url`), `assistant` (text and `tool_calls`), `tool` (`tool_call_id`, `content`) |
| `model` | See [Models and names](#models-and-names) |
| `stream`, `stream_options.include_usage` | SSE `chat.completion.chunk`s, a usage chunk, `data: [DONE]` |
| `max_completion_tokens` / `max_tokens` | `max_new_tokens` |
| `temperature`, `top_p`, `seed` | Passed through; absent = the model's defaults |
| `stop` | String or list: `stop_sequences` |
| `reasoning_effort` | Absent, `none` or `minimal`: no thinking. Anything else: thinking on, streamed as `delta.reasoning_content` |
| `tools`, `tool_choice` | Function tools. `tool_choice: "none"` sends none; other values let the model choose |
| `n` | Must be 1 |

Responses carry `finish_reason` `stop`, `length` (token limit) or `tool_calls`, and
`usage` (`prompt_tokens`, `completion_tokens`, `total_tokens`).

**Tools.** When the model calls a tool the response holds `tool_calls` (`id: "call_…"`,
`function.name`, `function.arguments` as a JSON string) and the client runs it. Send the
assistant message and a `tool` message with the result back, as with OpenAI. The server
keeps the model's own text for each call id (the newest 1024), so the model reads its
earlier turn in its native format; an id it never issued is rendered as
`<tool_call>{"name", "arguments"}</tool_call>`. Tool calling needs a pack with a tool
format (Qwen3, LFM2, Gemma 3/4).

**Images.** A user message with `image_url` parts goes to `--vlm`. The URL may be a
`data:` URL, an `http(s)` URL (fetched by the server) or a local file path. Images and
`tools` cannot be combined.

## Transcriptions

`POST /v1/audio/transcriptions` (multipart)

| Field | Meaning here |
|---|---|
| `file` | WAV, M4A/AAC, MP3, FLAC, CAF or AIFF, decoded by macOS. WebM and Ogg are refused (`unsupported_audio_format`) |
| `model` | See [Models and names](#models-and-names) |
| `language` | ISO code (`en`, `de`, …); absent = detect |
| `response_format` | `json` (`{"text"}`), `text`, `verbose_json`, `srt`, `vtt` |
| `timestamp_granularities[]` | `word` adds `words: [{word, start, end}]` to `verbose_json`; segments are always there |
| `stream` | `true`: SSE `transcript.text.delta` events, then `transcript.text.done` with the full text |
| `prompt`, `temperature` | Ignored |

The file is cut into windows in silence (`--vad`) and silent stretches are skipped. With
`stream=true` a delta is sent as soon as the words before the next window are settled, so
the deltas only ever add text; `done` carries the final transcript.

`verbose_json`: `{task: "transcribe", language, duration, text, segments: [{id, start,
end, text, …}], words}`. Segments end at `.`, `?`, `!` or after 12 s.

## Speech

`POST /v1/audio/speech` (JSON)

| Field | Meaning here |
|---|---|
| `input` | The text |
| `model` | See [Models and names](#models-and-names) |
| `voice` | A voice of the model (`paul`, `dave`, `jo` for NeuTTS). OpenAI's names (`alloy`, `nova`, …) and unknown voices use `--voice` |
| `response_format` | `mp3` (default), `wav`, `pcm` (16-bit little-endian mono at 24 kHz). `opus`, `aac`, `flac` are refused (`unsupported_response_format`) |
| `stream_format` | `sse`: `speech.audio.delta` events (`audio`: base64 of the chosen format), then `speech.audio.done` |
| `speed`, `instructions` | Ignored |

Audio is sent as the model makes it, whatever the format: the response body streams
(chunked), WAV with an open-ended header, MP3 frame by frame. The header
`X-Audio-Sample-Rate` gives the rate.

## Realtime transcription (WebSocket)

`ws://127.0.0.1:8000/v1/realtime?intent=transcription` speaks OpenAI's Realtime
transcription events over the SDK's live engine (VAD, streaming recognition, SmartTurn).

Client events:

| Event | Meaning |
|---|---|
| `session.update` (`session.type: "transcription"`, `audio.input.format {type: "audio/pcm", rate}`, `audio.input.transcription {model, language}`) | Settings before the first audio. Any rate; 24 kHz by default. The older `transcription_session.update` (`input_audio_format: "pcm16"`, `input_audio_transcription`) works too |
| `input_audio_buffer.append` (`audio`: base64 16-bit PCM) | Audio, in real time |
| `input_audio_buffer.commit` | End the open turn now (for a file that ends; live audio needs none) |
| `input_audio_buffer.clear` | Acknowledged |

Server events, per turn (`item_id` names the turn):

| Event | When |
|---|---|
| `session.created`, `session.updated` | Connect, settings |
| `input_audio_buffer.speech_started` (`audio_start_ms`) | The turn's first words |
| `conversation.item.input_audio_transcription.delta` (`delta`) | Committed text grows |
| `thestage.transcription.partial` (`committed`, `hypothesis`, `speaker_id`, `language`) | Every update, with the live tail (TheStage extension) |
| `input_audio_buffer.speech_stopped`, `input_audio_buffer.committed` (`previous_item_id`) | The turn ended |
| `conversation.item.input_audio_transcription.completed` (`transcript`) | The turn's formatted transcript |
| `error` (`error.code`, `error.message`) | A bad event or a capture failure; the session stays open |

**Capture on the Mac instead** (TheStage extension): `&source=microphone`, `system` or
`meeting` makes the server capture this Mac's microphone (with `--aec`), everything it
plays, or both; the client sends no audio and gets the same events. System and meeting
capture need macOS 14.2+ and the Screen & System Audio Recording permission for the app
running the server; without it the session reports `error` with code
`AUDIO_CAPTURE_PERMISSION_DENIED`.

One realtime session runs at a time; another connection gets `session_busy`.

## Speech from streaming text (WebSocket)

`ws://127.0.0.1:8000/v1/audio/speech/stream?voice=dave&format=pcm` (TheStage extension;
OpenAI has no text-streaming speech endpoint). For speaking an LLM's tokens as they
arrive.

| Direction | Message |
|---|---|
| server | `{"type": "session.created", "sample_rate": 24000}` |
| client | `{"type": "text", "text": "…"}`, any number of times |
| client | `{"type": "close"}` (speak what is left) or `{"type": "cancel"}` |
| server | Binary frames: `pcm` (16-bit LE), `wav` (header first) or `mp3`, as speech is made |
| server | `{"type": "done", "duration": 1.4}`, then the socket closes |

## Errors

HTTP errors use OpenAI's shape: `{"error": {"message", "type", "param", "code"}}`.

| Status | `code` | Cause |
|---|---|---|
| 400 | `model_not_found` | No model of that kind configured (`--vlm` for images) |
| 400 | `unsupported_audio_format` / `unsupported_response_format` | The upload or the requested output format |
| 400 | `invalid_param`, `missing_param` | A field the SDK rejected |
| 401 | `invalid_api_key` | `--api-key` set and not sent |
| 404 | `model_not_found` | Another repo with `--only-configured-models` |
| 500 | SDK error name | A model failed |

## Integrations

**`openai` client** (Python, JS, any language): `base_url="http://127.0.0.1:8000/v1"`,
any `api_key` (or the `--api-key`). See [`examples/openai_client.py`](../examples/openai_client.py).

**Open WebUI** (checked with Open WebUI from PyPI): chat, dictation and read-aloud. The env
file, launch command and a check script: [examples/open_webui](../examples/open_webui/README.md).
In short: `OPENAI_API_BASE_URL`, `AUDIO_STT_ENGINE=openai` +
`AUDIO_STT_OPENAI_API_BASE_URL`, `AUDIO_TTS_ENGINE=openai` +
`AUDIO_TTS_OPENAI_API_BASE_URL`, all `http://127.0.0.1:8000/v1` (from Docker:
`http://host.docker.internal:8000/v1`). Open WebUI needs ffmpeg: it converts browser
recordings (Opus/WebM) and M4A to mp3 before sending them. Turn off Open WebUI's built-in
tools (`DEFAULT_MODEL_METADATA={"capabilities": {"builtin_tools": false}}`): it adds them
to every browser chat, they overflow a small model's context, and the replies come back
empty (the server logs `empty reply … tools in the request`). Its voice call mode (OpenAI
Realtime conversations) is not supported.

**Hermes Agent** (checked with Hermes 0.19.0): the server is Hermes's voice, speech-to-text
and text-to-speech. Config, `.env` line and a check script:
[examples/hermes](../examples/hermes/README.md).

```yaml
tts:
  provider: openai
  openai: {base_url: http://127.0.0.1:8000/v1, model: tts-1, voice: dave}
stt:
  provider: openai
  openai: {base_url: http://127.0.0.1:8000/v1, api_key: local, model: whisper-1}
```

plus `VOICE_TOOLS_OPENAI_KEY=local` in `~/.hermes/.env` (Hermes's TTS reads its key only
from the environment). Two limits: Hermes asks for Ogg/Opus for Telegram voice bubbles,
which the server does not produce; and Hermes requires a chat model with 64K tokens of
context (its prompt is about 12K before the conversation), so its `model:` stays on
another provider — the on-device packs hold 1,256.

**Pipecat / LiveKit Agents / LangChain**: their OpenAI LLM, STT and TTS services take a
`base_url`; point it at `http://127.0.0.1:8000/v1`.

Checked here with the official `openai` client (`tests/test_server_models.py`: chat
streaming, tools round trip, image data URL, speech streaming and mp3, transcription
JSON and streaming, realtime transcription, the speech WebSocket) and with Hermes Agent's
own speech tools (`examples/hermes/check_voice.py`) and with Open WebUI's API
(`examples/open_webui/check.py`). The Pipecat and LiveKit settings follow those projects'
documentation and have not been run against this server.

## Differences from OpenAI

- Speech formats: `opus`, `aac`, `flac` are refused; `speed` and `instructions` ignored.
- Transcription ignores `prompt` and `temperature`; WebM and Ogg uploads are refused.
- Realtime serves transcription sessions only (no conversation mode yet); `commit` ends
  the turn by sending two seconds of silence through the engine.
- `reasoning_effort` only switches thinking on or off.
- Chat requests with both images and tools are refused.
