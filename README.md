# TheStage Apple SDK

On-device speech, language and audio inference for **iOS and macOS**
on Apple Silicon. The SDK ships compiled CoreML and MLX engines
through HuggingFace, auto-detects the best backend per device
(ANE / GPU / CPU), and exposes a unified `infer` / `infer_stream`
API for every pipeline. No server in the hot path.

## What's in this repo

- `TheStageCore.xcframework/` — pre-built SDK binary (`ios-arm64` +
  `macos-arm64` slices).
- `Package.swift` + `Sources/TheStageSDK/` — SwiftPM entry point for
  native Swift apps on iOS **and** macOS. `import TheStageSDK`.
- `examples/macos_swift_tts/` — minimal native-Swift streaming-TTS
  command-line demo (macOS, no Xcode). **Start here.**
- `examples/tts_front_stream/` — streaming neural TTS demo (Flutter,
  iPhone).
- `examples/voice_agent/` — full voice-assistant loop, mic → VAD →
  STT → LLM → streaming TTS (Flutter, iPhone).
- `plugin/thestage_apple_sdk/` — Flutter plugin over platform
  channels. **iOS only** for now.
- `docs/` — per-pipeline reference guides (LLM, Whisper, NeuTTS, VAD,
  Streaming, Voice Agent).
- `scripts/setup.sh` — one-time host setup (only needed for the
  Flutter examples).

---

## Quick start

### Fastest: hear it work on your Mac (no Xcode, no device)

A tiny native-Swift program that streams TTS straight to your
speakers:

```bash
cd examples/macos_swift_tts
export TS_API_TOKEN=th_…          # from app.thestage.ai
swift run
```

The first run downloads the NeuTTS engines from HuggingFace and caches
them; subsequent runs start instantly. Output-only playback needs no
microphone permission or entitlements. See
[examples/macos_swift_tts/README.md](./examples/macos_swift_tts/README.md).

### On a physical iPhone: the Flutter examples

```bash
# 1. One-time host setup (xcframework symlink + secrets bootstrap).
#    Idempotent — safe to re-run. (espeak is opt-in: --espeak, nano apps only.)
./scripts/setup.sh

# 2. Drop your API keys into the example you want to run.
cp examples/tts_front_stream/secrets.example.json \
   examples/tts_front_stream/secrets.json
$EDITOR examples/tts_front_stream/secrets.json
```

Open `examples/tts_front_stream/ios/Runner.xcodeproj` in Xcode, select
the **Runner** target, and under **Signing & Capabilities** set your
**Team** and a unique **Bundle Identifier**. Then run on a device:

```bash
cd examples/tts_front_stream
flutter pub get
flutter run --release \
    --dart-define-from-file=secrets.json \
    -d <YOUR_IPHONE_DEVICE_ID>
```

`flutter devices` lists attached devices. `examples/voice_agent`
follows the same recipe (it additionally needs `OPENAI_API_KEY` in its
`secrets.json`). See each example's `README.md` for app-specific notes.

---

## Prerequisites

| Requirement | Minimum | Tested with |
|-------------|---------|-------------|
| macOS | 15.0 | 15.6 |
| iOS | 18.0 | 18.6 |
| Xcode | 16.0 | 26.1 |
| Swift | 6.0 | 6.2.1 |
| Flutter (only for the Flutter examples) | 3.24 | 3.38.7 |
| Dart | 3.5 | 3.10.7 |
| Hardware | Apple Silicon Mac **or** physical iPhone / iPad | — |

The Simulator is **not** supported — MLX requires Metal on real
hardware. The Flutter plugin and the two Flutter example apps are
iOS-only; native Swift via SwiftPM runs on both iOS and macOS.

You'll need a TheStage API token from
[app.thestage.ai](https://app.thestage.ai). It's validated once on
first model start, then runs offline (7-day grace window if the device
is briefly disconnected). For the Flutter path you also need a Flutter
toolchain (`brew install flutter`, then `flutter config
--enable-swift-package-manager`).

---

## Use the SDK in your own app

### Native Swift (SwiftPM) — iOS and macOS

In Xcode: **File → Add Package Dependencies…**, paste this repo's URL,
and add the `TheStageSDK` product to your target. Or in `Package.swift`:

```swift
.package(url: "https://github.com/TheStageAI/AppleSDK.git", from: "1.0.0")
```

Then:

```swift
import TheStageSDK

let ai = TheStageAI.shared
try await ai.initialize(apiToken: "th_…")

// Construct any pipeline directly from an HF repo or local path.
// The same `on_load_progress` contract applies to all of them.
let llm = try await TheStageLLM(
    engines_path: "TheStageAI/Qwen3-0.6B",
    on_load_progress: { p in
        print("[\(p.model)] \(p.phase) \(Int(p.fraction * 100))%")
    }
)

let result = llm.infer(
    prompt: "Give me a one-line haiku about Swift.",
    max_new_tokens: 64
)
print(result.text)
```

Every pipeline (`TheStageLLM`, `WhisperPipeline`,
`NeuTTSMultilingualPipeline`, `NeuTTSNanoPipeline`) shares the same
constructor shape. Prefer the singleton
`TheStageAI.shared.start_model(...)` / `infer(model_name:input_json:)`
flow when you want lifecycle and JSON dispatch (e.g. driving the SDK
from Flutter). Both flows share the same on-disk cache and the same
`LoadProgress` events.

### Flutter (iOS)

The plugin bundles the native framework — nothing to build or link.
Three steps:

**1. Add the `git:` dependency** in your app's `pubspec.yaml`, pinned to
a tag:

```yaml
dependencies:
  thestage_apple_sdk:
    git:
      url: https://github.com/TheStageAI/AppleSDK.git
      path: plugin/thestage_apple_sdk
      ref: v1.0.0
```

**2. Configure the iOS project once:** enable SwiftPM and set the
deployment target to iOS 18.0+:

```bash
flutter config --enable-swift-package-manager
# then in Xcode: Runner target → General → Minimum Deployments → iOS 18.0
```

**3. Use it** (`flutter pub get`, then run on a physical device):

```dart
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

await TheStageFlutterSDK.initialize(api_token: 'th_…');

await TheStageFlutterSDK.start_model(
  model_name: 'llm',
  engines_path: 'TheStageAI/Qwen3-0.6B',
);

final result = await TheStageFlutterSDK.infer(
  model_name: 'llm',
  input_json: {
    'prompt': 'Give me a one-line haiku about Swift.',
    'max_new_tokens': 64,
  },
);
print(result[0]['text']);
```

Full install notes, the voice-agent API and the audio player live in the
[plugin README](./plugin/thestage_apple_sdk/README.md). The fastest way
to see a real app is to copy one of the `examples/` apps.

---

## Documentation

Full API reference, with parallel Swift and Flutter examples for every
pipeline, lives under [`docs/`](./docs/):

- [LLM](./docs/llm.md) — `TheStageLLM`: Qwen2 / Qwen3 / Gemma3 chat
  with streaming, KV cache, chat-template auto-detect.
- [Whisper ASR](./docs/whisper.md) — speech-to-text with automatic VAD
  chunking and long-audio stitching.
- [NeuTTS](./docs/tts.md) — multilingual + Nano TTS, batch +
  push-based streaming.
- [VAD](./docs/vad.md) — `SileroVAD`: stateful per-chunk speech
  detection.
- [Streaming](./docs/streaming.md) — TTS / LLM streaming patterns,
  back-pressure, sentence segmentation.
- [Voice Agent](./docs/voice_agent.md) — `TheStageVoiceAgent`:
  end-to-end voice assistant with barge-in.

---

## Reference

### Swift ↔ Flutter parity

The Swift singleton (`TheStageAI.shared`) and the Flutter
`TheStageFlutterSDK` mirror each other one-to-one. Pipeline
constructors (`TheStageLLM(...)`, `WhisperPipeline(...)`, etc.) are
Swift-only — Dart consumers always go through the JSON path.

| Operation | Swift | Flutter (Dart) |
|---|---|---|
| Initialize | `try await TheStageAI.shared.initialize(apiToken: "...")` | `await TheStageFlutterSDK.initialize(api_token: '...')` |
| Start a model | `try await ai.start_model(model_name:engines_path:config:on_load_progress:)` | `await TheStageFlutterSDK.start_model(model_name:, engines_path:, config:)` |
| Stop a model | `_ = try ai.stop_model(model_name: "llm")` | `await TheStageFlutterSDK.stop_model(model_name: 'llm')` |
| Single-shot inference | `try ai.infer(model_name:input_json:) -> [[String: Any]]` | `await TheStageFlutterSDK.infer(model_name:, input_json:) -> List<Map<String, dynamic>>` |
| Streaming inference | `try ai.infer_stream(model_name:input_json:) -> AsyncStream<InferenceStreamChunk>` | `TheStageFlutterSDK.infer_stream(model_name:, input_json:, stream_id:?) -> Stream<Map<String, dynamic>>` |
| Push text into a TTS stream | `streamer.send(text); streamer.stop_stream()` | `await TheStageFlutterSDK.send(stream_id:, text:); await TheStageFlutterSDK.finish_stream(stream_id:)` |
| Cancel a running stream | `streamer.stop_stream()` | `await TheStageFlutterSDK.stop_stream(stream_id:)` |
| Load progress | `on_load_progress: LoadProgressHandler?` on `start_model` / constructors | Global stream `TheStageFlutterSDK.on_progress` (`{model_name, phase, progress}`) |
| Audio buffer type | `[Float]` | `Float32List` (never `Float64List`) |

Note the one asymmetry that bites people: the Swift initializer is
`initialize(apiToken:)` (camelCase), while the Flutter call is
`initialize(api_token:)` (snake_case).

### Load progress

All public loaders accept an optional `on_load_progress:
LoadProgressHandler` that fires through four phases with a monotonic
fraction in `0...1`:

| Phase | Fraction band | Notes |
|---|---|---|
| `downloading` | 0.00 – 0.70 | HuggingFace repo download (skipped on cache hit) |
| `extracting` | 0.70 – 0.85 | Bundle unpack to local cache (skipped on cache hit) |
| `loading` | 0.85 – 0.99 | Pipeline construction |
| `ready` | 1.00 (terminal) | Emitted on success only |

The phase strings, fraction bands and terminal contract are identical
on both surfaces. See [docs/llm.md](./docs/llm.md#load-progress) for the
full event contract.

### Audio I/O contract

All audio crossing the public SDK surface uses **PCM `[Float]`, mono,
samples normalized to `[-1.0, 1.0]`**. Sample rate depends on the
pipeline:

| Pipeline | Direction | Sample rate | Frame / chunking |
|---|---|---|---|
| `SileroVAD` | input | **16 000 Hz** | exactly **512 samples** per `infer` (32 ms); stateful |
| `WhisperPipeline` | input | **16 000 Hz** | any length; auto-split into 10 s windows |
| `NeuTTSMultilingualPipeline` / `NeuTTSNanoPipeline` | output | **24 000 Hz** | streamer emits per-sentence chunks; batch emits one full `[Float]` |

The mic stack runs at 16 kHz mono for VAD/ASR; TTS output is always
24 kHz. Rather than hardcoding it, read the rate from the pipeline
(`tts.sample_rate`) — see `examples/macos_swift_tts`.

---

## Secrets

The Flutter example apps read tokens at build time via
`String.fromEnvironment(...)` and `--dart-define-from-file=secrets.json`.
Each ships a `secrets.example.json` template — copy it to `secrets.json`
and fill in your keys. `secrets.json` is covered by `.gitignore`; real
keys never belong in source. The macOS example reads `TS_API_TOKEN`
from the environment instead.

## License

See [LICENSE](LICENSE).
