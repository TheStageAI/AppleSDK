# tutor_tts

Mixed-language streaming TTS demo (iPhone). Pick a stock tagged phrase and
stream it on-device with **Qwen3-TTS**, calling `set_voice` between language
spans (`<en>…</en><es>…</es>` …).

| | |
| --- | --- |
| Platform | Physical iPhone, **iOS 18+** |
| SDK | AppleSDK tag `1.3.0` (`TheStageSDK` → xcframework) |
| Model | HF `TheStageAI/Qwen3-TTS-12Hz-0.6B-Base` (downloaded on first load) |
| Voices | Bundled `VoicePacks/tutor_<tag>/voice.json` (also on HF — see below) |

## What it exercises

- Qwen3-TTS `infer_stream` with per-span `set_voice`
- Language-tagged scripts (`LangParser` → ordered spans)
- Clone voice packs shipped next to the app (`VoicePacks/`)

## Prerequisites

- A TheStage API token — set as `TS_API_TOKEN` in `Secrets.xcconfig`
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Physical iPhone on iOS 18+

## Run

```bash
# from the AppleSDK repo root
./scripts/setup.sh    # one-time, if needed

cd examples/tutor_tts
cp Secrets.xcconfig.example Secrets.xcconfig
# edit Secrets.xcconfig → TS_API_TOKEN = <token from app.thestage.ai>

xcodegen generate
open TutorTTS.xcodeproj
```

In Xcode: set **Team** under Signing & Capabilities, then Run (Release) on a
device.

Or:

```bash
./build_and_run.sh
# DEVICE_ID=<udid> ./build_and_run.sh
```

## App flow

1. **Load model** — downloads/compiles Qwen3-TTS on first launch
2. Select a stock phrase (or full mini-lesson)
3. Tagged script is shown as `<en>…</en><es>…</es>`
4. **Play stream** — each span: `set_voice` → `infer_stream` → live PCM

## Voice packs (HF)

The five `tutor_{en,es,fr,de,pt}` packs ship in this example. The same packs
are published at:

**https://huggingface.co/TheStageAI/Qwen3-TTS-Tutor-VoicePacks**

so you can reuse them outside the demo (`voice.json` per language folder).

## Notes

- Bundle id placeholder: `com.example.tutortts` — change to your team id.
- This example pins the published `TheStageSDK` SwiftPM product. Point
  `Package.swift` at a local checkout only when developing against an
  unpublished SDK binary.
