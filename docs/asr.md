# ASR (Speech-to-Text)

On-device speech recognition. Two shipping families share the same
`thestage_asr` JSON path (`start_model` + `infer`) and the same **16
kHz mono float** audio contract:

- **Whisper** (`WhisperPipeline`) — mel → encoder → decoder, optional
  internal Silero VAD, long-audio windows, Swift push streamer for live
  partials.
- **Qwen3-ASR** (`Qwen3ASRPipeline`) — audio encoder + Qwen3 decoder
  (audio prefix). Greedy decode; language `"auto"` or a hint. Batch /
  agent path only — no push streamer.

Flutter uses the singleton (no Dart constructors). Prefer device `npu`
on Apple Silicon. Omit `revision:` → fleet pin.

> **Main features**
>
> - **Two families, one path**: Whisper large-v3-turbo and Qwen3-ASR
>   0.6B both load through `start_model("stt")` and return the same
>   `ASRResult` shape.
> - **16 kHz mono float contract**: `AudioIO.load_wav(...)` resamples
>   files for you; from memory, feed `[Float]` (Swift) or `Float32List`
>   (Flutter) in `[-1, 1]`.
> - **Long-audio windowing**: Whisper stitches 10 s windows with
>   optional `overlap_seconds`; Qwen3-ASR splits into 30 s segments and
>   joins the transcripts.
> - **Language auto-detect (Qwen3-ASR)**: `language: "auto"` returns the
>   transcript plus a detected language token. Whisper needs an explicit
>   ISO code.
> - **Live partials (Whisper, Swift)**: `open_streamer(language:
>   partial_interval_ms:)` gives `partials` + authoritative `finish()`
>   + `flush()` / `cancel()` for barge-in.
> - **Internal Silero VAD (Whisper)**: skips silence and stops
>   hallucinated text out of the box; opt out when an upstream gate
>   already trimmed speech.
> - **Voice-agent parity**: both families work as the agent's STT
>   provider via auto-routing.

## In this page

Here we will cover the following topics:

- [**Supported models**](#supported-models): feature matrix (streaming, language, windowing, VAD).
- [**API surface**](#api-surface): Swift constructor / Flutter singleton, batch and streaming.
- [**Quick start**](#quick-start): batch WAV, live partials, Flutter one-shot.
- [**Audio contract**](#audio-contract): the 16 kHz mono float rule and its escape hatches.
- [**Configuration**](#configuration): `overlap_seconds`, `use_internal_vad`, `language`, tokens.
- [**Streaming API**](#streaming-api): Whisper `send` / `partials` / `flush` / `finish` / `cancel`.
- [**Result object**](#result-object): `ASRResult` and its Flutter JSON keys.
- [**Lifecycle**](#lifecycle): initialize → construct → infer / stream → cleanup.
- [**Usage Guides**](#usage-guides): WAV from disk, PCM from memory, sample rate, long audio, mic → infer, partials, disable VAD, Whisper vs Qwen3-ASR, run Qwen3-ASR (auto / hint / batch), non-English, Flutter JSON keys, live captions in a product UI.
- [**Troubleshooting**](#troubleshooting): empty transcripts, dropped words at seams, slow long files, wrong language, VAD edge cases, load failures, Flutter audio-type errors.

## Supported models

| Model | HF repo | Base | Device | Fleet pin |
|-------|---------|------|--------|-----------|
| TheWhisper Large V3 Turbo | `TheStageAI/thewhisper-large-v3-turbo` | Whisper-large-v3-turbo | NPU | v1.1 |
| Qwen3-ASR 0.6B | `TheStageAI/Qwen3-ASR-0.6B` | 0.6B | NPU | v1.1 |

| Feature | Whisper turbo | Qwen3-ASR 0.6B |
|---------|:-------------:|:--------------:|
| Batch `infer` (16 kHz mono) | yes | yes |
| Flutter / `start_model` | yes | yes |
| Language hint | Whisper codes (en, fr, …) | auto / code / English name |
| Internal Silero VAD | yes | — |
| Long-audio windowing | ~10 s | ~30 s segments |
| Push streamer (live partials) | yes (Swift) | — |
| Voice Agent STT | yes | yes (via `thestage_asr`) |

## API surface

| Purpose | Swift | Flutter |
|---------|-------|---------|
| Init (Whisper) | `try await WhisperPipeline(engines_path:device:overlap_seconds:use_internal_vad:)` | `start_model(model_name:"stt", engines_path:, config:)` |
| Init (Qwen3-ASR) | `try await Qwen3ASRPipeline(engines_path:device:)` | same `start_model` — auto-routed |
| One-shot | `stt.infer(audio:language:config:)` → `ASRResult` | `infer(model_name:"stt", input_json:{'audio':…})` |
| Streaming (Whisper) | `stt.open_streamer(language:partial_interval_ms:)` | use [Voice Agent](./voice_agent.md) |
| Progress | `on_load_progress` | `TheStageFlutterSDK.on_progress` |
| Cleanup | drop the pipeline | `stop_model(model_name:"stt")` |

## Quick start

**Swift — batch transcript from a WAV:**

```swift
import TheStageSDK

try await TheStageAI.shared.initialize(apiToken: "your-api-token")

let stt = try await WhisperPipeline(
    engines_path: "TheStageAI/thewhisper-large-v3-turbo",
    device: "npu",
    use_internal_vad: true
)

let samples = try AudioIO.load_wav(
    path: "/path/to/clip.wav",
    target_sample_rate: 16_000
)

let result = stt.infer(audio: samples, language: "en")
print(result.text)
```

**Swift — live partials via `open_streamer`:**

```swift
let streamer = stt.open_streamer(language: "en", partial_interval_ms: 600)
Task {
    for await partial in streamer.partials {
        captionLabel.text = partial     // cosmetic live text
    }
}

// push 16 kHz mono chunks from your mic:
streamer.send(micChunk)
// at end of turn:
let finalText = try await streamer.finish()
```

**Flutter — one-shot JSON:**

```dart
await TheStageFlutterSDK.initialize(api_token: 'your-api-token');
await TheStageFlutterSDK.start_model(
  model_name: 'stt',
  engines_path: 'TheStageAI/thewhisper-large-v3-turbo',
  config: {'use_internal_vad': true},
);

final out = await TheStageFlutterSDK.infer(
  model_name: 'stt',
  input_json: {
    'audio': pcm16k as Float32List,   // 16 kHz mono float
    'language': 'en',
  },
);
print(out[0]['transcription']);
```

## Audio contract

Audio must be **16 kHz mono float** in `[-1, 1]` before `infer` —
`infer` does not auto-resample. Helper:
`AudioIO.load_wav(path:target_sample_rate:)`. Flutter must pass
`Float32List` (not `Float64List`). See
[Audio I/O Contract](./README.md#audio-io-contract).

## Configuration

| Knob | When it applies | Notes |
|------|-----------------|-------|
| `overlap_seconds` | Whisper init | Long-audio window overlap (default 0) |
| `use_internal_vad` | Whisper init | Bundled Silero pre-pass (default true) |
| `language` | per call | Whisper codes; Qwen3 accepts `auto` / code / English name |
| `max_new_tokens` | per call | Cap per-window decode |
| `return_tokens` | per call | Include token IDs in the result |
| `partial_interval_ms` | Whisper streamer | Cadence of partial captions (default 600 ms) |

## Streaming API

Whisper only — Swift-only for now (Flutter should use
[Voice Agent](./voice_agent.md) for live captions).

| API | Role |
|-----|------|
| `send(_:)` | Push `[Float]` 16 kHz frames (any size) |
| `partials` | `AsyncStream<String>` — cosmetic live captions |
| `flush()` | Commit at a VAD pause |
| `finish()` | Authoritative end-of-turn transcript |
| `cancel()` | Abort (barge-in) |

## Result object

| Field | Meaning |
|-------|---------|
| `text` / `transcription` | Transcript (Swift `text`, JSON `transcription`) |
| `token_count` | Decoded tokens |
| `decode_seconds` | Decoder wall time |
| `tokens` | Only when `return_tokens` is set |

## Lifecycle

1. `initialize(apiToken:)` once per process.
2. Construct a pipeline or `start_model` — first call downloads and
   compiles the pack.
3. Call `infer` / open a streamer. Streamers are single-use — call
   `finish()` or `cancel()` before opening the next one.
4. Drop the pipeline (Swift) or `stop_model` (Flutter) when done.

## Usage Guides

Jump to a recipe:

- [How do I load a WAV from disk for `infer`?](#how-do-i-load-a-wav-from-disk-for-infer)
- [How do I pass PCM from memory?](#how-do-i-pass-pcm-from-memory)
- [Why does the wrong sample rate break quality?](#why-does-the-wrong-sample-rate-break-quality)
- [How do I handle long audio?](#how-do-i-handle-long-audio)
- [How do I go from live mic → batch `infer`?](#how-do-i-go-from-live-mic-batch-infer)
- [How do I stream partials (`open_streamer` / `finish` / `flush` / `cancel`)?](#how-do-i-stream-partials-open-streamer-finish-flush-cancel)
- [How do I disable internal VAD?](#how-do-i-disable-internal-vad)
- [When should I pick Whisper vs Qwen3-ASR?](#when-should-i-pick-whisper-vs-qwen3-asr)
- [How do I run Qwen3-ASR (auto-detect / hint / batch)?](#how-do-i-run-qwen3-asr-auto-detect-hint-batch)
- [How do I transcribe non-English audio?](#how-do-i-transcribe-non-english-audio)
- [What JSON key holds the transcript on Flutter?](#what-json-key-holds-the-transcript-on-flutter)
- [How do I get live captions in a product UI?](#how-do-i-get-live-captions-in-a-product-ui)

### How do I load a WAV from disk for `infer`?

Use `AudioIO.load_wav` — it loads mono Float PCM and resamples to
**16 kHz**. Do **not** peak-normalize.

**Fixture:** [`assets/asr_sample.wav`](./assets/asr_sample.wav)

**Example output** (Whisper turbo, NPU):

| Metric | Value |
|---|---|
| Transcript | `The quick brown fox jumps over the lazy dog.` |
| Word recall | 100% |
| Wall | ~0.115 s |
| tok/s | ~256.5 |
| rtfx | ~22.53 |

**Swift:**

```swift
import TheStageSDK

try await TheStageAI.shared.initialize(apiToken: "your-api-token")

let stt = try await WhisperPipeline(
    engines_path: "TheStageAI/thewhisper-large-v3-turbo",
    device: "npu"
)

let samples: [Float] = try AudioIO.load_wav(
    path: "docs/assets/asr_sample.wav",
    target_sample_rate: 16_000
)
let result: ASRResult = stt.infer(audio: samples, language: "en")
print(result.text)
// The quick brown fox jumps over the lazy dog.
```

`AudioIO.load_wav` → `[Float]` (16 kHz mono, typically in `[-1, 1]`).

### How do I pass PCM from memory?

```swift
// Your buffer: 16 kHz mono Float in [-1, 1]
let pcm_floats: [Float] = /* mic / decoder / network PCM */
let result: ASRResult = stt.infer(audio: pcm_floats, language: "en")
print(result.text)
```

| Rule | |
|---|---|
| Swift type | `[Float]` |
| Rate | **16 kHz** (resample with `AudioIO.load_wav` or your converter) |
| Channels | **Mono** |
| Scale | Float `[-1, 1]` — Int16 → `Float(i16) / 32768` |
| Loudness normalize | **No** by default |

**Flutter:**

```dart
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';
import 'dart:typed_data';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

await TheStageFlutterSDK.start_model(
  model_name: 'stt',
  engines_path: 'TheStageAI/thewhisper-large-v3-turbo',
);

// Float32List — 16 kHz mono, values in [-1.0, 1.0]
final Float32List audioSamples = /* your PCM */;
final result = await TheStageFlutterSDK.infer(
  model_name: 'stt',
  input_json: {
    'audio': audioSamples,
    'language': 'en',
  },
);
final String transcript = result[0]['transcription'] as String;
print(transcript);
```

Always `initialize` before constructing / `start_model`.

### Why does the wrong sample rate break quality?

Feed 44.1 / 48 kHz without resampling → time-warped speech → empty or
nonsense transcripts. Always land on **16 kHz mono Float**
(`AudioIO.load_wav` does this for files). There is no internal
resampler inside `WhisperPipeline.infer`.

### How do I handle long audio?

You do **not** need to split manually. The pipeline windows at **10 s**
and stitches transcripts. For words that straddle seams, set
`overlap_seconds` (1–2 s is typical):

```swift
let stt = try await WhisperPipeline(
    engines_path: "TheStageAI/thewhisper-large-v3-turbo",
    overlap_seconds: 2
)
let full_recording: [Float] = /* 16 kHz mono PCM */
let result: ASRResult = stt.infer(audio: full_recording, language: "en")
```

```dart
await TheStageFlutterSDK.start_model(
  model_name: 'stt',
  engines_path: 'TheStageAI/thewhisper-large-v3-turbo',
  config: {'overlap_seconds': 2},
);
```

Windows run sequentially — a 60 s file is roughly 6× one window. Keep
internal VAD on (default) to skip silence, or pre-segment speech.

### How do I go from live mic → batch `infer`?

Simplest live path: capture at 16 kHz mono, accumulate one utterance,
then `infer` once.

```swift
import TheStageSDK
import AVFoundation

let engine = AVAudioEngine()
let input = engine.inputNode
let format = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 16000, channels: 1, interleaved: false
)!
var accumulated: [Float] = []

input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
    let ptr = buffer.floatChannelData![0]
    let frame: [Float] = Array(UnsafeBufferPointer(
        start: ptr, count: Int(buffer.frameLength)
    ))
    accumulated.append(contentsOf: frame)
}
engine.prepare()
try engine.start()
// … wait for end of utterance …
engine.stop()
input.removeTap(onBus: 0)

let result: ASRResult = stt.infer(audio: accumulated, language: "en")
print(result.text)  // String
```

If the session runs at 44.1 / 48 kHz, resample to 16 kHz before `infer`.

### How do I stream partials (`open_streamer` / `finish` / `flush` / `cancel`)?

Use when you need live captions that grow while the user speaks.
**Swift only** on `WhisperPipeline`. Flutter → [Voice Agent](./voice_agent.md).

```swift
let streamer = stt.open_streamer(language: "en", partial_interval_ms: 600)

let captions = Task {
    for await text in streamer.partials {
        print("partial: \(text)")   // committed-so-far; never retracts
    }
}

for await frame: [Float] in microphone_frames {  // 16 kHz mono
    streamer.send(frame)
    if vad_detected_pause { streamer.flush() }  // long turns stay snappy
}

let final_text: String = await streamer.finish()  // authoritative
await captions.value
print("final: \(final_text)")

// Barge-in / abandon turn:
streamer.cancel()
```

- `partials` = cosmetic UI; `finish()` = trusted full transcript.
- `flush()` at VAD pauses commits settled text and trims so later passes
  stay fast.
- `cancel()` skips the final decode.

### How do I disable internal VAD?

When an upstream gate (e.g. `TheStageVoiceAgent`) already trimmed speech,
a second Silero pass only adds latency:

```swift
let stt = try await WhisperPipeline(
    engines_path: "TheStageAI/thewhisper-large-v3-turbo",
    use_internal_vad: false
)
```

```swift
try await ai.start_model(
    model_name: "stt",
    engines_path: "TheStageAI/thewhisper-large-v3-turbo",
    config: ["use_internal_vad": false]
)
```

```dart
await TheStageFlutterSDK.start_model(
  model_name: 'stt',
  engines_path: 'TheStageAI/thewhisper-large-v3-turbo',
  config: {'use_internal_vad': false},
);
```

With VAD off, silence can hallucinate text — only disable when the
buffer is known speech.

### When should I pick Whisper vs Qwen3-ASR?

Both families load through the same `thestage_asr` path — pick by
what your product needs, not by API shape.

| You need… | Pick | Why |
|-----------|------|-----|
| Live captions / partials during speech | **Whisper** | Only Whisper exposes `open_streamer` today. |
| Language auto-detect (no hint) | **Qwen3-ASR** | Accepts `language: "auto"`; Whisper requires an explicit code. |
| Long files (minutes) with word-level continuity | **Whisper** | 10 s windows + `overlap_seconds` handles seams. |
| ChatML-friendly transcript for downstream LLM prompting | **Qwen3-ASR** | Output is `language {Name}<asr_text>{transcript}` — trivial to parse. |
| Smallest working NPU footprint | **Whisper turbo** | Smaller decoder, faster prefill on Apple Silicon. |
| Voice Agent STT | Either | The agent routes automatically from the bundle. |

Everything else (`infer` signature, `ASRResult`, `AudioIO.load_wav`
requirements, Flutter JSON) is identical.

### How do I run Qwen3-ASR (auto-detect / hint / batch)?

Qwen3-ASR runs the audio as a **prefix** into a Qwen3 decoder — the
result is the transcript plus a detected language token. Silence
returns an empty transcript, not an error.

**Swift — one-shot with auto language:**

```swift
import TheStageSDK

try await TheStageAI.shared.initialize(apiToken: "your-api-token")

let stt = try await Qwen3ASRPipeline(
    engines_path: "TheStageAI/Qwen3-ASR-0.6B",
    device: "npu"
)

let samples: [Float] = try AudioIO.load_wav(
    path: "/path/to/clip.wav",
    target_sample_rate: 16_000
)

// language: "auto" (default) — model detects language.
// Alternatives: an ISO code ("en", "zh", …) or a full English name ("Japanese").
let result: ASRResult = stt.infer(audio: samples, language: "auto")
print(result.text)
```

**Swift — hint the language when you already know it (faster, more accurate):**

```swift
let jp = stt.infer(audio: samples, language: "Japanese")   // or "ja"
print(jp.text)
```

**Flutter — same start_model path; auto-routing picks Qwen3-ASR from the bundle:**

```dart
await TheStageFlutterSDK.start_model(
  model_name: 'stt',
  engines_path: 'TheStageAI/Qwen3-ASR-0.6B',
);

final result = await TheStageFlutterSDK.infer(
  model_name: 'stt',
  input_json: {
    'audio': audioSamples,        // Float32List, 16 kHz mono, [-1, 1]
    'language': 'auto',           // or 'en' / 'English'
  },
);
print(result[0]['transcription']);
```

Qwen3-ASR has **no push streamer** — for live captions use Whisper's
`open_streamer(...)` or the [Voice Agent](./voice_agent.md).

### How do I transcribe non-English audio?

Whisper does **not** auto-detect language. Set `language` explicitly
(ISO 639-1). Wrong code → English decode of foreign speech → nonsense.
Qwen3-ASR does auto-detect (`language: "auto"`) — see the section
above.

| Language | Code | Language | Code |
|---|---|---|---|
| English | `en` | Japanese | `ja` |
| French | `fr` | Korean | `ko` |
| German | `de` | Chinese | `zh` |
| Spanish | `es` | Arabic | `ar` |
| Portuguese | `pt` | Hindi | `hi` |
| Russian | `ru` | Italian | `it` |

```swift
let samples: [Float] = /* 16 kHz mono PCM */
let result: ASRResult = stt.infer(audio: samples, language: "fr")
print(result.text)  // String
```

```dart
final Float32List audioSamples = /* 16 kHz mono PCM */;
final result = await TheStageFlutterSDK.infer(
  model_name: 'stt',
  input_json: {'audio': audioSamples, 'language': 'ja'},
);
final String transcript = result[0]['transcription'] as String;
print(transcript);
```

### What JSON key holds the transcript on Flutter?

Use **`transcription`** (`String`), not `text`:

```dart
final String transcript = result[0]['transcription'] as String;
print(transcript);
```

Optional: `token_count` (`int`), `decode_seconds` (`double`), `tokens`.

### How do I get live captions in a product UI?

- **Swift standalone:** `open_streamer` above.
- **Flutter / full assistant loop:** [Voice Agent](./voice_agent.md) —
  `asr_streaming`, `partial_transcripts` / `user_request_partial`, and
  the chat-UI guide. The agent runs streaming ASR internally; Flutter
  does not expose `WhisperPipeline.open_streamer`.

## Troubleshooting

### Empty or inaccurate transcript

Usually wrong audio format.

1. Confirm **exactly 16000 Hz** before `infer`.
2. Mono only.
3. Float in `[-1.0, 1.0]` (`Int16 / 32768.0`).
4. Confirm the buffer actually contains speech.

```swift
let int16_samples: [Int16] = /* … */
let float_samples: [Float] = int16_samples.map { Float($0) / 32768.0 }
let result: ASRResult = stt.infer(audio: float_samples, language: "en")
```

### Words drop at chunk boundaries

Default `overlap_seconds: 0`. Raise to `1`–`2` for long files.

### Slow on long recordings

Windows are sequential. Keep `use_internal_vad: true`, pass only speech
regions, or stream shorter turns instead of one giant buffer.

### Wrong language / nonsense text

Set `language` to the spoken language. Default is `"en"`.

### Short utterances eaten / hallucinated silence

Internal VAD may drop very short bursts; disable only if you already
gated speech. Conversely, VAD-off on silence → hallucinations.

### Model load fails

Call `initialize(apiToken:)` first. Prefetch on a splash screen if cold
download hangs the UI. Prefer `device: "npu"`.

### Flutter audio type errors

Use `Float32List` for `audio`. `Float64List` will not round-trip
correctly on the platform channel.

## Load Progress / Prefetch / Cleanup

### Load progress

```swift
let stt = try await WhisperPipeline(
    engines_path: "TheStageAI/thewhisper-large-v3-turbo",
    on_load_progress: { p in
        print("[\(p.model)] \(p.phase) \(Int(p.fraction * 100))%")
    }
)
```

Same handler on `start_model` / `prefetch_engines`. Phases:
`downloading` → `extracting` → `loading` → `ready` (cache hits skip
download/extract). Full contract:
[Load Progress](./README.md#load-progress).

**Flutter:**

```dart
TheStageFlutterSDK.on_progress.listen((event) {
  if (event['model_name'] != 'stt') return;
  final phase = event['phase'] as String?;
  final fraction = event['progress'] as double?;
  print('[stt] $phase ${(fraction ?? 0) * 100}%');
});

await TheStageFlutterSDK.start_model(
  model_name: 'stt',
  engines_path: 'TheStageAI/thewhisper-large-v3-turbo',
);
```

### Prefetch

```swift
let engines_dir = try await ai.prefetch_engines(
    repo_id: "TheStageAI/thewhisper-large-v3-turbo"
)
let stt = try await WhisperPipeline(engines_path: engines_dir)
```

### Cleanup

Drop the `WhisperPipeline` reference, or:

```swift
_ = try ai.stop_model(model_name: "stt")
```

```dart
await TheStageFlutterSDK.stop_model(model_name: 'stt');
```
