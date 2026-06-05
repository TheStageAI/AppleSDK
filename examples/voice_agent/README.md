# voice_agent

Full voice-assistant demo: speak into the mic, get a spoken response
back, all orchestrated natively. STT runs on-device (Whisper), the LLM
step calls OpenAI's hosted API, and TTS streams back through the
on-device NeuTTS pipeline.

## What it exercises

- Mic capture + on-device VAD + Whisper STT.
- A cloud LLM provider (OpenAI by default) reached over HTTPS — swap in
  any provider by changing the LLM fields in `lib/settings_model.dart`
  (`llm_provider` / `llm_endpoint` / `llm_model`).
- Streaming NeuTTS playback with barge-in.
- The `TheStageVoiceAgent` native orchestrator (state stream + typed
  ports for transcripts and LLM deltas).

## How the code is laid out

The app is deliberately split so the data flow is easy to follow:

- `lib/voice_agent_controller.dart` — the single place that subscribes to
  `agent.events` and turns each event into typed UI state. The doc comment
  at the top maps every event to what it draws (e.g. `user_speech` ->
  transcript bubble, `response_delta` -> streaming LLM bubble). **Start
  here to see how transcription and LLM output reach the screen.**
- `lib/voice_chat_screen.dart` — a "dumb" view: it only renders the
  controller's fields and wires the Start / Stop / Interrupt buttons.
- `lib/settings_model.dart` — model ids, LLM provider config, and the
  interruption/VAD knobs sent to `agent.start(config:)`.

## Prerequisites

- A TheStage API token — set as `TS_API_TOKEN` in `secrets.json`.
- An OpenAI API key — set as `OPENAI_API_KEY` in `secrets.json`. (Swap
  for another provider if you prefer; just update the LLM call site
  and the dart-define name.)
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
  speaking, tapping the mic interrupts playback and starts listening.
- All STT and TTS work happens on-device. The only network hop is the
  LLM call.
- The agent's state machine and outputs are exposed over a Flutter event
  channel — see `lib/voice_agent_controller.dart` for how those events
  are mapped to the UI.
