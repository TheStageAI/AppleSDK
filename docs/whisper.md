# Whisper ASR (Speech-to-Text)

On-device speech recognition using Whisper. `WhisperPipeline` handles
mel-spectrogram, encoder and decoder, with automatic VAD chunking and
long-audio stitching.

Flutter consumers go through the singleton `start_model` + `infer`
JSON path — there is no direct `WhisperPipeline` constructor on Dart.
Both surfaces share the same on-disk cache and response shape.

## Basic Usage

**Swift** — direct constructor (recommended):

```swift
import TheStageSDK

let ai = TheStageAI.shared
try await ai.initialize(apiToken: "your-api-token")

let stt = try await WhisperPipeline(
    engines_path: "TheStageAI/thewhisper-large-v3-turbo"  // HF repo or local
)

// Transcribe audio (16 kHz mono Float, see Audio I/O Contract).
let result = stt.infer(audio: audio_samples, language: "en")
print(result.text)  // "Hello, how are you today?"
```

**Flutter** — JSON path:

```dart
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';
import 'dart:typed_data';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

await TheStageFlutterSDK.start_model(
  model_name: 'stt',
  engines_path: 'TheStageAI/thewhisper-large-v3-turbo',
);

// audio_samples: Float32List, 16 kHz mono, samples in [-1.0, 1.0].
final result = await TheStageFlutterSDK.infer(
  model_name: 'stt',
  input_json: {
    'audio': audio_samples,
    'language': 'en',
  },
);
print(result[0]['transcription']);
```

## Inputs / Outputs

| Direction | Type | Description |
|---|---|---|
| input  `audio` | `[Float]` | 16 kHz mono PCM, samples in `[-1.0, 1.0]`, any length. |
| input  `language` | `String` (default `"en"`) | Whisper language code: `en`, `fr`, `de`, `es`, `pt`, `ja`, `ko`, `zh`, `ar`, `hi`, `ru`, … |
| input  `config.max_new_tokens` | `Int?` | Cap per-window decode. |
| input  `config.return_tokens` | `Bool` (default `false`) | Include token IDs in `ASRResult`. |
| output `ASRResult.text` | `String` | Transcribed text. |
| output `ASRResult.token_count` | `Int` | Total decoded tokens (sum across windows). |
| output `ASRResult.decode_seconds` | `Double` | Decoder wall time. |
| output `ASRResult.tokens` | `[Int]?` | Token IDs (only if `return_tokens == true`). |

## Audio I/O

- 16 kHz mono `[Float]`, samples normalized to `[-1.0, 1.0]`.
- Long buffers are split internally into the bundle's `chunk_seconds`
  windows. The shipping `TheStageAI/thewhisper-large-v3-turbo` uses
  **10 s** windows; the value is read from the bundle so older 10 / 15 /
  30 s exports also work.
- Overlap between windows is configurable via the `overlap_seconds`
  constructor argument (default `0`). Useful on streaming captures to
  avoid losing words straddling a chunk boundary.
- Mismatched-rate input is **not** auto-resampled — convert your mic
  capture to 16 kHz mono Float32 before calling `infer`.
- `WhisperPipeline.split_audio(audio:chunk_samples:overlap_samples:)`
  and `WhisperPipeline.stitch_tokens(...)` are exposed for callers
  that want manual control.

See [Audio I/O Contract](./README.md#audio-io-contract) for the
shared format used across VAD / ASR / TTS.

## Streaming (live transcription)

`open_streamer` turns the pipeline into a push-based live transcriber that
mirrors the TTS streamer: push audio as it arrives with `send(_:)`, read
stable, monotonically-growing partials off `partials`, then `finish()` for
the authoritative end-of-turn transcript. A single serial worker re-decodes
the growing buffer and commits stable text via LocalAgreement, so it is safe
to drive straight from a real-time microphone capture.

```swift
// One streamer per turn (utterance). 16 kHz mono Float, same as `infer`.
let streamer = stt.open_streamer(language: "en")

// Drain partials concurrently with sending audio.
let captions = Task {
    for await text in streamer.partials {
        print("partial: \(text)")   // committed-so-far, grows monotonically
    }
}

// Feed mic frames as they arrive (any frame size; e.g. 100 ms blocks).
for await frame in microphone_frames {          // [Float] @ 16 kHz mono
    streamer.send(frame)
    // At a VAD pause, finalize the settled segment and trim the buffer so
    // later passes stay fast on long turns (optional but recommended):
    if vad_detected_pause { streamer.flush() }
}

// End of turn → authoritative transcript (also closes `partials`).
let final_text = await streamer.finish()
await captions.value
print("final: \(final_text)")
```

Behavior and knobs:

- `partials` is **cosmetic/live**; `finish()` is the **trusted** result and
  always covers the complete audio (including the last word).
- `flush()` at VAD pauses keeps per-pass latency flat over long turns: it
  commits settled text and decodes only the uncommitted tail afterward.
- `cancel()` aborts the turn and closes `partials` without a final decode
  (use it for barge-in).
- `partial_interval_ms` (default `600`) bounds how often partial passes run.
- Convert mic input to 16 kHz mono Float32 first — input is **not** resampled.
- Streaming transcription is a **Swift-direct** API on `WhisperPipeline`.
  For live speech-to-text on Flutter, use the Voice Agent
  ([voice_agent.md](./voice_agent.md)), which runs streaming ASR internally.

## Internal VAD Chunking

`WhisperPipeline` includes a Silero-VAD pre-pass that finds speech
segments before transcribing — this is the "automatic VAD chunking"
referenced above. Disable it (`use_internal_vad: false`) when an
upstream consumer (e.g. `TheStageVoiceAgent`) has already gated the
audio with its own VAD; running Silero a second time on a pre-trimmed
buffer just adds latency. Through the singleton API this is
`config: ["use_internal_vad": false]`.

## Singleton API (`TheStageAI.shared`)

```swift
try await ai.start_model(
    model_name: "stt",                            // any handle you choose
    engines_path: "TheStageAI/thewhisper-large-v3-turbo"
)

let json = try ai.infer(
    model_name: "stt",
    input_json: [
        "audio": audio_samples,    // [Float] / [Double] / MLMultiArray, 16 kHz mono
        "language": "en",          // optional, default "en"
        "return_tokens": true       // optional, include token IDs
    ]
)
let text = json[0]["transcription"] as! String
```

JSON response keys: `transcription` (`String`), `token_count` (`Int`),
`decode_seconds` (`Double`), `tokens` (`[Int]`, optional).

The Flutter `TheStageFlutterSDK.infer` call hits this exact JSON path,
so the response keys above apply unchanged on Dart. `audio` crosses
the platform channel as `Float32List`; do not promote to `Float64List`.

## Full Constructor

```swift
let stt = try await WhisperPipeline(
    engines_path: "TheStageAI/thewhisper-large-v3-turbo",
    device: "npu",                       // "npu" | "gpu" | "cpu"
    devices: nil,                        // optional per-component override
    overlap_seconds: 0,                  // chunk overlap for long audio
    use_internal_vad: true,              // bundled SileroVAD pre-pass
    revision: "main",                    // HF revision; ignored locally
    on_load_progress: nil                // see "Load Progress" below
)
```

`TheStageAI.shared.initialize(apiToken:)` must have succeeded before
this call returns.

## Load Progress

`on_load_progress` is **optional**. When set, the handler fires through
four phases with a monotonic `fraction` in `0...1`:

```swift
let stt = try await WhisperPipeline(
    engines_path: "TheStageAI/thewhisper-large-v3-turbo",
    on_load_progress: { p in
        print("[\(p.model)] \(p.phase) \(Int(p.fraction * 100))%")
    }
)
```

The same `on_load_progress` parameter is accepted by
`TheStageAI.shared.start_model(...)` and
`TheStageAI.shared.prefetch_engines(...)`. For the full event contract
see [Load Progress in the index](./README.md#load-progress).

**Flutter:**

```dart
TheStageFlutterSDK.on_progress.listen((event) {
  if (event['model_name'] != 'stt') return;
  final phase    = event['phase']    as String?;   // downloading | extracting | loading | ready
  final fraction = event['progress'] as double?;   // 0.0 ... 1.0, monotonic
  print('[stt] $phase ${(fraction ?? 0) * 100}%');
});

await TheStageFlutterSDK.start_model(
  model_name: 'stt',
  engines_path: 'TheStageAI/thewhisper-large-v3-turbo',
);
```

## Prefetch Engines

```swift
let engines_dir = try await ai.prefetch_engines(
    repo_id: "TheStageAI/thewhisper-large-v3-turbo"
)

// Later — instant load, no network:
let stt = try await WhisperPipeline(engines_path: engines_dir)
```

## Cleanup

`WhisperPipeline` is a normal Swift object — drop the reference to
release it. When you used the singleton API:

```swift
_ = try ai.stop_model(model_name: "stt")
```

**Flutter:**

```dart
await TheStageFlutterSDK.stop_model(model_name: 'stt');
```
