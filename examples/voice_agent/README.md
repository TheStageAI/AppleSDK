# voice_agent

Full on-device voice-assistant demo: mic → VAD / turn detection → ASR →
local LLM (with optional tool calling) → streaming TTS, orchestrated by
`TheStageVoiceAgent`.

## What it exercises

- Mic capture, on-device VAD, turn detection, and Whisper / Qwen3 ASR.
- On-device LLM (default `TheStageAI/LFM2.5-350M`) via HuggingFace engines
  (optional offline `BundledModels` mode in Settings).
- `llm_tools` + `tool_started` / `tool_ended` events and
  `TheStageAgentState.tool_calling`.
- Streaming TTS (Qwen3-TTS or NeuTTS) with barge-in.
- The Flutter bridge (`TheStageVoiceAgentFlutter`) — state stream and typed
  ports for transcripts and LLM deltas.

## How the code is laid out

- `lib/backend/voice_agent_controller.dart` — subscribes to `agent.events`
  and maps each event into UI state. **Start here** to see how
  transcription, tool calls, and LLM deltas reach the screen.
- `lib/backend/settings_model.dart` — model ids, voice / language knobs,
  interruption / VAD settings, and `toConfig()` for `agent.start`.
- `lib/ui/voice_chat_screen.dart` — view only: Start / Stop / Interrupt and
  transcript rendering.

## Prerequisites

- A TheStage API token — set as `TS_API_TOKEN` in `secrets.json`.
- A physical iPhone on iOS 18+. Microphone permission is requested at
  launch.

## Run

```bash
# from the repo root
./scripts/setup.sh    # one-time, idempotent

cp examples/voice_agent/secrets.example.json \
   examples/voice_agent/secrets.json
$EDITOR examples/voice_agent/secrets.json
```

Open `examples/voice_agent/ios/Runner.xcodeproj` in Xcode and set the
Team + Bundle Identifier under **Signing & Capabilities** (e.g.
`com.yourcompany.voice-agent-demo`).

```bash
cd examples/voice_agent
flutter pub get
flutter run --release \
    --dart-define-from-file=secrets.json \
    -d <YOUR_IPHONE_DEVICE_ID>
```

## Notes

- The mic icon controls both capture and barge-in. While TTS is
  speaking (or a tool is running), tapping the mic interrupts and
  returns to listening.
- STT, LLM, and TTS all run on-device when using the default HF / local
  stack. HuggingFace downloads happen on first launch and are cached.
- Model revisions come from the SDK `ModelRevisionMap` — do not pass
  `*_revision` keys unless you intentionally override.
