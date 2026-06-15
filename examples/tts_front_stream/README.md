# tts_front_stream

Streaming neural TTS demo. Type some text, hit play, audio chunks start
streaming back from the device while the rest of the sentence is still
being generated.

## What it exercises

- `TheStageFlutterSDK.initialize(api_token:)`
- `TheStageFlutterSDK.start_model(model_type: 'neutts', …)` with
  HuggingFace engine prefetch.
- `TheStageFlutterSDK.infer_stream(...)` in push mode (per-chunk audio
  events).
- `TheStageAudioPlayer` for low-latency playback.

## Prerequisites

- A TheStage API token — set as `TS_API_TOKEN` in `secrets.json`.
- A physical iPhone or iPad on iOS 18+.

## Run

```bash
# from the repo root
./scripts/setup.sh    # one-time, idempotent

cp examples/tts_front_stream/secrets.example.json \
   examples/tts_front_stream/secrets.json
$EDITOR examples/tts_front_stream/secrets.json
```

Open `examples/tts_front_stream/ios/Runner.xcodeproj` in Xcode, select
the **Runner** target, and under **Signing & Capabilities** set:

- Team — your Apple Developer team.
- Bundle Identifier — anything unique you own, e.g.
  `com.yourcompany.tts-stream-demo`.

Then:

```bash
cd examples/tts_front_stream
flutter pub get
flutter run --release \
    --dart-define-from-file=secrets.json \
    -d <YOUR_IPHONE_DEVICE_ID>
```

Use `flutter devices` to find the device id.

## Notes

- The first launch downloads the NeuTTS engines from HuggingFace
  (~hundreds of MB) and caches them under the app's Application
  Support directory. Subsequent launches start instantly.
- Audio plays as 24 kHz mono float PCM. The streaming chunk cadence
  can be tuned via `TTSStreamConfig` (see the in-app settings panel).
