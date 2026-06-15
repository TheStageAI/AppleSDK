# macos_swift_tts

The fastest way to hear the SDK work: a tiny native-Swift command-line
program that loads NeuTTS and streams two phrases to your Mac speakers.
No Xcode, no signing, no device — just `swift run`.

## What it exercises

- `TheStageAI.shared.initialize(apiToken:)`
- `NeuTTSMultilingualPipeline` loaded straight from a HuggingFace repo.
- `open_streamer()` push-mode streaming — audio chunks play as they're
  produced (`streamer.send(...)` / `streamer.stop_stream()`).
- `AudioStreamPlayer` for low-latency playback, driven at the pipeline's
  own `sample_rate`.

## Prerequisites

- An Apple Silicon Mac on macOS 15+ with Swift 6.
- A TheStage API token from [app.thestage.ai](https://app.thestage.ai).

## Run

```bash
cd examples/macos_swift_tts
export TS_API_TOKEN=th_…
swift run
```

That's it. Playback is output-only, so no microphone permission or
entitlements are needed.

## Notes

- The first run downloads the NeuTTS engines from HuggingFace (~hundreds
  of MB) and caches them under your home directory; subsequent runs start
  instantly.
- Audio plays as 24 kHz mono float PCM. The program reads the rate from
  `tts.sample_rate` rather than hardcoding it, so it stays correct if the
  codec rate ever changes.
- `main.swift` is a plain top-level script — read it top to bottom; each
  numbered step maps to one stage of the flow.
