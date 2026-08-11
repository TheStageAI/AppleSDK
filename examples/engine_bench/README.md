# EngineBench

iOS benchmark app for the **TheStage Apple SDK `1.2.0`**.
Measure LLM decode tok/s + TTFT, streaming TTS, ASR, and VLM (camera /
gallery) on a physical iPhone — all engines load from **Hugging Face**
(`TheStageAI/*`) via ``ModelRevisionMap`` (no model weights are shipped
in this example).

| | |
| --- | --- |
| Example version | **`1.2.0`** (see [`VERSION`](./VERSION)) |
| SDK pin | Local `Package.swift` at repo root (`import TheStageSDK`) |
| Platforms | iPhone, **iOS 18+** (no Simulator) |
| Models | HF only — first launch downloads + caches per model |

## What you get

- **LLM** tab — Generate (streaming) + Benchmark (warmup + N quiet runs)
- **TTS** tab — NeuTTS nano-multilingual + Qwen3-TTS
- **ASR** tab — Whisper turbo + Qwen3-ASR (mic or fixture)
- **VLM** tab — LFM2.5-VL (camera / gallery) + Generate / Benchmark
- **Share** — export the session as a JSON file (device id + metrics)

## Prerequisites

1. Apple Silicon Mac, **Xcode 16+**, [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
2. Physical iPhone on **iOS 18+**, unlocked + trusted
3. API token from [app.thestage.ai](https://app.thestage.ai)
4. This example lives inside a checkout of
   [TheStageAI/AppleSDK](https://github.com/TheStageAI/AppleSDK) at tag
   **`1.2.0`** (the `project.yml` depends on `../..`)

## Setup (once)

```bash
cd examples/engine_bench

# 1) API token — edit the shipped Secrets.xcconfig (do not commit a real token)
#   TS_API_TOKEN = th_…

# 2) Signing — generate the Xcode project, then set your Team
xcodegen generate
open EngineBench.xcodeproj
```

In Xcode → **EngineBench** target → **Signing & Capabilities**:

- Team — your Apple Developer team
- Bundle Identifier — anything unique you own (default
  `com.example.enginebench`)

## Run

### Option A — Xcode

Select your iPhone, **Product → Run** (prefer **Release** for real
numbers; Debug is much slower).

### Option B — CLI

```bash
cd examples/engine_bench
./build_and_run.sh
# or: DEVICE_ID=<devicectl-id> ./build_and_run.sh
```

`xcrun devicectl list devices` prints connected device ids.

## Hugging Face models

Pickers use these repos (revision comes from the SDK map for this line —
do **not** hardcode `vA.B` unless you intentionally override):

| Tab | HF repo |
| --- | --- |
| LLM | `TheStageAI/LFM2.5-230M`, `LFM2.5-350M`, `Qwen3-0.6B`, `gemma-3-1b-it` |
| TTS | `TheStageAI/neutts-nano-multilingual`, `Qwen3-TTS-12Hz-0.6B-Base` |
| ASR | `TheStageAI/thewhisper-large-v3-turbo`, `Qwen3-ASR-0.6B` |
| VLM | `TheStageAI/LFM2.5-VL-450M` (SDK 1.2 map → HF `v1.2`) |

First load of each model downloads hundreds of MB and compiles on-device
(progress UI in-app). Later launches reuse the SDK cache.

## Notes

- Always measure **Release** builds for tok/s / TTFT / RTF.
- Online `initialize` is required (token validated before any pipeline).
- This example does **not** ship bundled engine packs or internal upload
  scripts — engines always come from Hugging Face.
