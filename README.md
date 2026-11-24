# TheStage Apple SDK

![On-Device Apple SDK](docs/assets/on-device-apple-sdk-banner.png)

Run LLMs, speech recognition, text-to-speech and voice agents **on the
device**, on **iPhone and Mac**. You pass a Hugging Face model id; the SDK
downloads a pack optimized for the device's chip, picks the Neural Engine,
GPU or CPU, and runs it. After `initialize`, **inference never leaves the
device** — there is no server in the hot path.

- **Fast:** up to **4.1× faster** decoding with speculative decoding
  ([results](#speculative-decoding)).
- **Easy on the battery:** up to **5.1× less power** than MLX on the GPU
  ([results](#built-for-battery--not-just-toks)).
- **One API** for Swift, Flutter and Python, from one model call to a full
  voice agent.

| | |
| --- | --- |
| Version | **`1.6.0`** (pin this tag / SwiftPM `exact:`) |
| Checksums | [`RELEASE.md`](./RELEASE.md) — binary sha256 and the pinned model packs |
| Platforms | iOS **18+**, macOS **15+**, Apple Silicon only |
| Surfaces | Native Swift (`TheStageSDK`) · Flutter plugin (iOS) · Python (`thestage_sdk`, macOS) |
| Engines | Hugging Face `TheStageAI/*`; this SDK pins a revision per model ([`RELEASE.md`](./RELEASE.md)) |
| Token | [app.thestage.ai](https://app.thestage.ai) — online `initialize` required |

> **Not supported:** iOS Simulator, Intel Macs, Android, server-side inference.

---

## Try it without writing code: Edgent

**Edgent** is our edge gallery app for iPhone and Mac. It runs TheStage AI
models on the Apple Neural Engine and shows what the SDK's engines do in a
real product:

| Engine | What you can try in Edgent |
| --- | --- |
| **Note-taking** | Record a meeting or a lecture and get a live transcript with speakers, all on the device |
| **Dictation** | Hold a shortcut on the Mac and speak into any app |
| **Voice assistant** | Talk to an on-device assistant that listens, thinks, calls tools and answers by voice |
| **Model gallery** | Download models and test them: chat, vision, speech-to-text, text-to-speech |

![Edgent on Mac and iPhone](docs/assets/edgent-mac-iphone.jpg)

**Get the free beta on TestFlight:**
[testflight.apple.com/join/wygq1BJd](https://testflight.apple.com/join/wygq1BJd)
— one link for iPhone (iOS 18+) and Mac (Apple silicon, macOS 15+). On a
Mac, switch the platform to **macOS** on the TestFlight page before you
install.

Edgent stands on the work of great model builders. The models it runs come
from [Liquid AI](https://huggingface.co/LiquidAI) (LFM),
[Google](https://huggingface.co/google) (Gemma, EmbeddingGemma),
[Qwen](https://huggingface.co/Qwen) (Qwen3, Qwen3-ASR, Qwen3-TTS),
[OpenAI](https://huggingface.co/openai) (Whisper),
[NVIDIA](https://huggingface.co/nvidia) (Parakeet),
[Neuphonic](https://huggingface.co/neuphonic) (NeuTTS),
[Kyutai](https://huggingface.co/kyutai) (Pocket TTS),
[Silero](https://github.com/snakers4/silero-vad) (VAD) and
[Pipecat](https://huggingface.co/pipecat-ai) (Smart Turn). We optimize
them for Apple devices; the credit for the models is theirs.

---

## Built for battery — not just tok/s

On-device generation on the **Apple Neural Engine** draws a fraction of the
power of GPU paths like MLX — phones stay cooler, laptops stay on battery,
and sustained chat / voice agents remain practical.

![Power draw during generation — Gemma3-1B, TheStage ANE vs MLX GPU](docs/assets/power-draw-gemma3-1b.png)

*Gemma3-1B, sustained load. MacBook M3 Max via macmon; iPhone 13 via battery
drain. **~5.1×** less power on M3 Max and **~3.5×** on iPhone 13 vs MLX
(GPU). Lower is better.*

Speed and latency charts live under [Performance](#performance).

---

## Read this first

**Humans** — do the [60-second Mac quick start](#quick-start), then pick
Swift or Flutter under [Integrate](#integrate). Dive into contracts only
when something breaks.

**Agents / coding assistants** — treat this file as the index, then open
[`docs/llms.txt`](./docs/llms.txt) and the linked page for the pipeline you
touch. Hard rules:

1. Always `initialize` **before** any pipeline / `start_model`.
2. Pin the SDK to tag **`1.6.0`** (do not float `from:`).
3. Pass HF repo ids like `"TheStageAI/Qwen3-0.6B"` — omit `revision` unless
   you intentionally override (defaults track this SDK line).
4. Audio is **mono `Float` / `Float32List` in `[-1.0, 1.0]`** — never
   `Float64` / Int16 without converting.
5. Do **not** invent device IDs, seat accounting, or crypto details — see
   [licensing](./docs/licensing.md).

```text
initialize (online) ──► start_model / Pipeline(...) ──► infer / infer_stream
        │                         │
        │                         ▼
        │              HF download + cache (first time)
        ▼
   process session OK     inference fully on-device
```

---

## Table of contents

1. [Try it without writing code: Edgent](#try-it-without-writing-code-edgent)
2. [Built for battery](#built-for-battery--not-just-toks)
3. [What's in this repo](#whats-in-this-repo)
4. [Capabilities & model fleet](#capabilities--model-fleet)
5. [Performance](#performance)
6. [Quick start](#quick-start)
7. [Prerequisites](#prerequisites)
8. [Integrate](#integrate)
9. [Mental model](#mental-model)
10. [Contracts](#contracts) (audio · progress · Swift↔Flutter)
11. [Documentation map](#documentation-map)
12. [Troubleshooting](#troubleshooting)
13. [Secrets & license](#secrets--license)

---

## What's in this repo

| Path | Role |
| --- | --- |
| `TheStageCore.xcframework/` | Pre-built binary (`ios-arm64` + `macos-arm64`) |
| `Package.swift` + `Sources/TheStageSDK/` | SwiftPM entry — `import TheStageSDK` |
| `plugin/thestage_apple_sdk/` | Flutter plugin (iOS only); vendors the xcframework |
| `bindings/` | Python binding for macOS (`thestage_sdk`) and the Swift bridge it drives — see [`bindings/README.md`](./bindings/README.md) |
| `examples/` | Demos pinned to this SDK version — see [`examples/README.md`](./examples/README.md) |
| `examples/macos_swift_tts/` | **Start here** — native Swift streaming TTS on Mac (no Xcode) |
| `examples/engine_bench/` | iPhone LLM / TTS / ASR / VLM benches (Hugging Face engines) |
| `examples/voice_agent/` | Flutter mic → VAD → STT → LLM → TTS with barge-in |
| `examples/voice_agent_custom_nodes/` | Flutter custom nodes + ephemeral VLM captions |
| `docs/` | Per-pipeline guides + [`llms.txt`](./docs/llms.txt) agent index |
| `scripts/setup.sh` | One-time host setup for Flutter examples |

---

## Capabilities & model fleet

Everything below is the production fleet of SDK
**`1.6.0`**; the revision of each pack is pinned by the SDK
and listed in [`RELEASE.md`](./RELEASE.md). Pass the HF id as `engines_path`
(or construct the typed pipeline with the same string).

| Task | HF engines | Swift entry | Notes |
| --- | --- | --- | --- |
| Chat LLM | `TheStageAI/Qwen3-0.6B` | `TSLLM` | Also `gemma-3-1b-it`, LFM2.5-230M / 350M / 1.2B, LFM3-1.7B |
| Chat LLM (multimodal root) | `TheStageAI/gemma-4-E2B-it` | `TSVLM` | Gemma-4 E2B, text-only for now (encoders attach later) |
| VLM | `TheStageAI/LFM2.5-VL-450M` | `TSVLM` | Image + prompt → text |
| ASR | `TheStageAI/thewhisper-large-v3-turbo` | `WhisperPipeline` | Also `Qwen3-ASR-0.6B`, `parakeet-tdt-0.6b-v3` |
| Speakers | `TheStageAI/Nemotron-3-Diarization`, `TheStageAI/speaker-id-v2` | `ASREngine` with `speakers` | Who said what, saved voices; see [diarization.md](./docs/diarization.md) |
| TTS | `TheStageAI/neutts-nano-multilingual` | `NeuTTSMultilingualPipeline` | Prefer nano for voice agents |
| TTS | `TheStageAI/Qwen3-TTS-12Hz-0.6B-Base` | `Qwen3TTSPipeline` | Auto-routed from bundle layout |
| TTS | `TheStageAI/phonon-31m-en` | `PhononTTSPipeline` | Pocket TTS family: also `pocket-tts-18m-en` and the `pocket-tts-100m-<lang>` language packs |
| Embeddings | `TheStageAI/embeddinggemma-2` | `EmbeddingPipeline` | Text, image, audio and video in one space; see [embedding.md](./docs/embedding.md) |
| VAD | `TheStageAI/silero-vad` | `SileroVAD` | 512-sample chunks @ 16 kHz |
| Turn detect | `TheStageAI/smart-turn-v3` | via `TSVoiceAgent` | DNN end-of-turn |
| Speaker ID | `TheStageAI/redimnet2` | `SpeakerEmbedding` | 192-d embedding, 2 s window |
| Full agent | compose above | `TSVoiceAgent` | See [voice_agent.md](./docs/voice_agent.md) |

**Out of this release (do not pin in new apps):** full
`neutts-multilingual`, English espeak `neutts` / `NeuTTSNanoPipeline`,
wake-word, YOLO.

Model cards (contracts + acknowledgments):
[huggingface.co/TheStageAI](https://huggingface.co/TheStageAI).

---

## Performance

Release-build comparisons vs common on-device stacks. Device class and thermals
matter — treat these as relative guidance, not an SLA.

### Speculative decoding

A small drafter model proposes several tokens and the main model checks them
in one pass. Decoding gets **2.4–4.1× faster**, and with greedy sampling the
output is token-for-token the same as plain decoding.

![Gemma-4-E2B-it — plain vs speculative decoding, tokens per second](docs/assets/specdec-gemma-4-e2b.png)

![LFM2.5-230M — plain vs speculative decoding, tokens per second](docs/assets/specdec-lfm2.5-230m.png)

| Model | Device | Plain | Speculative | Speed-up |
| --- | --- | --- | --- | --- |
| LFM2.5-230M | M3 Max | 284 tok/s | **741 tok/s** | **2.61×** |
| LFM2.5-230M | iPhone 17 Pro | 324 tok/s | **776 tok/s** | **2.39×** |
| LFM2.5-350M | M3 Max | 194 tok/s | **581 tok/s** | **2.99×** |
| LFM2.5-350M | iPhone 17 Pro | 247 tok/s | **605 tok/s** | **2.45×** |
| LFM2.5-1.2B | M3 Max | 95 tok/s | **378 tok/s** | **3.99×** |
| Gemma-4-E2B-it | M3 Max | 45 tok/s | **188 tok/s** | **4.14×** |
| Gemma-4-E2B-it | iPhone 17 Pro | 46 tok/s | **184 tok/s** | **4.01×** |
| Qwen3-ASR-0.6B | M3 Max | 60 tok/s | **183 tok/s** | **3.06×** |
| Qwen3-ASR-0.6B | iPhone 17 Pro | 67 tok/s | **196 tok/s** | **2.94×** |

*Mean decode tokens per second, greedy sampling, after warm-up. LLMs on
held-out tool-use and function-calling prompts; ASR on multilingual speech.
Method and all charts:
[4× Faster On-Device LLMs: Speculative Decoding on the ANE](https://app.thestage.ai/blog/speculative-decoding-on-the-ane?id=23).*

You do not turn anything on: a model that supports it uses it whenever
`temperature` is `0`. See `speculative_decoding` in [llm.md](./docs/llm.md).

### Decode throughput vs MLX (GPU)

Gemma-3-1B-it tokens/sec across iPhones — TheStage on ANE vs MLX on GPU
(higher is better):

![Gemma-3-1B-it decode speed — TheStage AI vs MLX GPU](docs/assets/tps-gemma-3-1b-it.png)

### Time to first token

LFM2.5-350M TTFT — TheStage stays in the low teens of ms while MLX stretches
on older phones (lower is better):

![LFM2.5-350M time to first token — TheStage AI vs MLX GPU](docs/assets/ttft-lfm2.5-350m.png)

### ANE runtime bake-off (same chip)

Qwen3-0.6B on **iPhone 17 Pro**, all paths on the Neural Engine — TheStage
SDK vs CoreML-LLM and CoreAI (higher is better):

![Qwen3-0.6B decode speed — ANE runtimes on iPhone 17 Pro](docs/assets/qwen3-0.6b-ane-runtimes-iphone17.png)

Power / efficiency (intro highlight):
[Built for battery](#built-for-battery--not-just-toks).

---

## Quick start

### 60 seconds on Mac (no Xcode, no device)

```bash
cd examples/macos_swift_tts
export TS_API_TOKEN=th_…          # from app.thestage.ai
swift run
```

First run downloads NeuTTS engines and caches them; later runs start cold
from disk. Playback-only — no mic permission. Details:
[examples/macos_swift_tts/README.md](./examples/macos_swift_tts/README.md).

### Physical iPhone (Flutter)

```bash
./scripts/setup.sh                # idempotent; espeak only if you need nano-EN
cp examples/voice_agent/secrets.example.json \
   examples/voice_agent/secrets.json
# edit secrets.json → TS_API_TOKEN
```

In Xcode (`examples/voice_agent/ios/Runner.xcodeproj`): set **Team** +
unique **Bundle Identifier**, then:

```bash
cd examples/voice_agent
flutter pub get
flutter run --release \
    --dart-define-from-file=secrets.json \
    -d <YOUR_IPHONE_DEVICE_ID>
```

`examples/voice_agent_custom_nodes` is the same recipe (+ `OPENAI_API_KEY` if you use
the cloud LLM provider).

---

## Prerequisites

| Requirement | Minimum | Notes |
| --- | --- | --- |
| macOS | 15.0 | Apple Silicon Mac |
| iOS | 18.0 | Physical iPhone / iPad |
| Xcode | 26 | For device signing / iOS apps. The SDK binary is built with Xcode 27; older Xcode versions are not tested |
| Swift | 6.2 | SwiftPM (the toolchain of Xcode 26) |
| Flutter / Dart | 3.24 / 3.5 | Flutter examples + plugin only |
| Network | once per process | Required for `initialize` and first engine download |

```bash
# Flutter path only
brew install flutter
flutter config --enable-swift-package-manager
```

---

## Integrate

### Native Swift (iOS + macOS)

Xcode → **File → Add Package Dependencies…** → this repo URL → product
`TheStageSDK`. Or:

```swift
.package(
    url: "https://github.com/TheStageAI/AppleSDK.git",
    exact: Version(1, 6, 0)
)
```

```swift
import TheStageSDK

let ai = TheStageAI.shared
try await ai.initialize(api_token: "th_…")

let llm = try await TSLLM(
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

Two ways to drive models (same cache, same progress events):

| Style | When to use |
| --- | --- |
| Typed pipelines (`TSLLM(...)`, `WhisperPipeline(...)`, …) | Native Swift apps — compile-time APIs |
| `TheStageAI.shared.start_model` / `infer` / `infer_stream` | JSON lifecycle, Flutter, dynamic model sets |

### Flutter (iOS)

```yaml
dependencies:
  thestage_apple_sdk:
    git:
      url: https://github.com/TheStageAI/AppleSDK.git
      path: plugin/thestage_apple_sdk
      ref: 1.6.0
```

```bash
flutter config --enable-swift-package-manager
# Xcode → Runner → Minimum Deployments → iOS 18.0
```

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

More: [plugin README](./plugin/thestage_apple_sdk/README.md). Fastest
path to a working UI: copy an `examples/` app.

---

## Mental model

### Lifecycle

1. **`initialize(api_token:)`** — online token check + device seat
   registration. Fails offline / on network errors. Once per process
   when reachable; after success, **inference is on-device** for that
   process.
2. **Load** — `Pipeline(engines_path:)` or `start_model(...)`. First hit
   downloads the HF revision for this SDK line into Application Support
   (not purged by iOS, excluded from iCloud backup).
3. **Infer** — batch `infer` or streaming `infer_stream` / TTS streamer.
4. **Stop** — `stop_model` / drop pipeline references to free memory.

### Revisions

Omit `revision:` in normal apps. SDK **`1.6.0`** pins the revision of every model
([`RELEASE.md`](./RELEASE.md)). Override only when
you intentionally pin an older engine tag.

### Init & seats (product)

- Seat = `(apiToken, deviceId)` — see [licensing.md](./docs/licensing.md).
- Pricing / plans: Service Request at
  [app.thestage.ai/contact](https://app.thestage.ai/contact).
- Do not document or depend on how `deviceId` is derived.

---

## Contracts

### Audio I/O

All public audio is **PCM mono**, samples in **`[-1.0, 1.0]`**.

| Pipeline | Direction | Rate | Framing |
| --- | --- | --- | --- |
| `SileroVAD` | in | **16 kHz** | exactly **512** samples / call (stateful) |
| `WhisperPipeline` / Qwen3-ASR | in | **16 kHz** | any length; SDK windows long audio |
| NeuTTS / Qwen3-TTS | out | **24 kHz** | streamer = chunks; batch = one buffer |
| `SpeakerEmbedding` | in | **16 kHz** | **2.0 s** window (pad/trim) |

Prefer `tts.sample_rate` over hardcoding. Mic path for agents is 16 kHz;
TTS playback is 24 kHz — resample at the edge if you mix them.

Swift: `[Float]` · Flutter: **`Float32List` only**.

### Load progress

Optional `on_load_progress` (Swift) / `TheStageFlutterSDK.on_progress`
(Flutter). Phases are monotonic `0...1`:

| Phase | Band | Notes |
| --- | --- | --- |
| `downloading` | 0.00 – 0.70 | HF fetch (skipped on cache hit) |
| `extracting` | 0.70 – 0.85 | Unpack (skipped on cache hit) |
| `loading` | 0.85 – 0.99 | Pipeline construction |
| `ready` | 1.00 | Success only |

### Swift ↔ Flutter parity

| Operation | Swift | Flutter |
| --- | --- | --- |
| Initialize | `TheStageAI.shared.initialize(api_token:)` | `TheStageFlutterSDK.initialize(api_token:)` |
| Start | `ai.start_model(...)` | `start_model(...)` |
| Stop | `ai.stop_model(model_name:)` | `stop_model(model_name:)` |
| Batch | `ai.infer(model_name:input_json:)` | `infer(...)` |
| Stream | `ai.infer_stream(...)` → `AsyncStream` | `infer_stream(...)` → `Stream` |
| TTS push | `streamer.send` / `stop_stream` | `send` / `finish_stream` / `stop_stream` |
| Progress | per-call `on_load_progress` | global `on_progress` |
| Typed pipelines | yes | no — JSON path only |

---

## Documentation map

| Doc | Open when you need… |
| --- | --- |
| [`docs/llms.txt`](./docs/llms.txt) | Agent-oriented symbol + page index |
| [llm.md](./docs/llm.md) | Chat, streaming tokens, sampling, KV |
| [asr.md](./docs/asr.md) | TheWhisper, Qwen3-ASR, Parakeet: clips, live captions, languages |
| [diarization.md](./docs/diarization.md) | Speakers: who said what, live and from a file |
| [vlm.md](./docs/vlm.md) | Image + prompt → text |
| [tts.md](./docs/tts.md) | NeuTTS, Qwen3-TTS, Pocket TTS: voices, streaming |
| [embedding.md](./docs/embedding.md) | Embeddings for search over text, images, audio, video |
| [vad.md](./docs/vad.md) | Silero chunk contract |
| [audio_nodes.md](./docs/audio_nodes.md) | Default audio, custom PCM providers, node graph |
| [streaming.md](./docs/streaming.md) | Back-pressure, sentence segmentation |
| [voice_agent.md](./docs/voice_agent.md) | Full loop, barge-in, smart-turn knobs |
| [loading.md](./docs/loading.md) | `load_models`, warm-up, staying specialized, `delete_model` |
| [types.md](./docs/types.md) | Shared configs, results, `SamplingParams` |
| [speaker_embedding.md](./docs/speaker_embedding.md) | Enroll / verify |
| [licensing.md](./docs/licensing.md) | Token, seats, offline rules |
| [logging.md](./docs/logging.md) | Support breadcrumbs |
| [product_terms.md](./docs/product_terms.md) | Commercial / legal pointer |

---

## Troubleshooting

### Known issues (1.6.0)

- **Voice tool-call streaming / parsing:** filler text and tool-call markup
  can appear interleaved on the same stream, so TTS may start speaking while
  a tool call is still being recognized or executed. Some edge cases in tool
  call parsing remain. **Planned fix in the next release.**

### Symptoms and fixes

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `notInitialized` / pipelines throw at construct | Forgot `initialize` | Call it once at app start (online) |
| Init fails offline / flaky network | Online validation required | Reconnect; retry `initialize` |
| Simulator build / Metal errors | Simulator unsupported | Use a physical device or Apple Silicon Mac |
| First infer very slow | HF download | Wait for `ready`; later runs use cache |
| Flutter audio glitches / NaNs | `Float64List` or wrong rate | Use `Float32List`; match table above |
| TTS / ASR “wrong” model type | Bundle auto-route | Pass the correct HF repo; see tts.md |
| SwiftPM / plugin resolve fails | Floating version | Pin `exact:` / `ref: 1.6.0` |
| Voice agent never commits turn | Thresholds / mode | See smart-turn knobs in voice_agent.md |
| Tool call + spoken filler overlap / odd parse | Known streaming gap this release | See [Known issues](#known-issues-160); fix planned next release |

---

## Secrets & license

Flutter examples load tokens via `--dart-define-from-file=secrets.json`
(from `secrets.example.json`). Keep real keys out of git. The macOS
example uses `TS_API_TOKEN` in the environment.

License: [LICENSE](LICENSE). Commercial terms:
[product_terms.md](./docs/product_terms.md).
