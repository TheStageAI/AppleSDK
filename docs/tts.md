# TTS (Text-to-Speech)

On-device neural text-to-speech with batch and push-based streaming.
Public pipelines:

- **`NeuTTSMultilingualPipeline`** — NeuTTS multilingual / nano-multilingual.
- **`Qwen3TTSPipeline`** — Qwen3-TTS (12 Hz talker + MTP + codec).

> **Release note:** English espeak nano (`TheStageAI/neutts` /
> `NeuTTSNanoPipeline`) is **not** in the current HF fleet — it needs an
> app-side espeak phonemizer. For the current `@v1.1` fleet prefer
> `neutts-nano-multilingual`. Full `neutts-multilingual` is temporarily
> out of the sealed release set until its talker ships `llm/graph.json`.

Flutter / `start_model` go through the TTS family router: the bundle
layout selects Qwen3-TTS vs NeuTTS automatically (see
[Auto-routing](#auto-routing-start_model)). There is no direct TTS
constructor on Dart. All surfaces share the same on-disk cache and
24 kHz PCM output contract.

## Qwen3-TTS

**Swift** — direct constructor:

```swift
import TheStageSDK

try await TheStageAI.shared.initialize(apiToken: "your-api-token")

let tts = try await Qwen3TTSPipeline(
    engines_path: "TheStageAI/Qwen3-TTS-12Hz-0.6B-Base",
    voice_id: "b_ref"   // default
)

let result = tts.infer(text: "Hello, world!")
// result.samples: [Float] @ 24 kHz mono
```

**Flutter** — same JSON path as NeuTTS; pass the Qwen3-TTS repo:

```dart
await TheStageFlutterSDK.start_model(
  model_name: 'tts',
  engines_path: 'TheStageAI/Qwen3-TTS-12Hz-0.6B-Base',
  config: {'voice_id': 'b_ref'},
);
```

| Item | Default / notes |
|---|---|
| HF example | `TheStageAI/Qwen3-TTS-12Hz-0.6B-Base` |
| `voice_id` | `"b_ref"` |
| Sample rate | **24 000 Hz** mono |
| Sampling | Bundle defaults (talker ~`temperature=0.9`, `top_k=50`); override via `TTSGenerationConfig` / JSON `config` |
| Streaming | Same push `infer_stream` / `open_streamer` patterns as NeuTTS |

## Auto-routing (`start_model`)

When you `start_model` a TTS handle without picking a Swift subclass, the
SDK inspects the bundle:

1. Spec has MTP (or legacy `talker/` / `qwen3_tts_spec.json`) → **Qwen3-TTS**
   (`voice_id` default `"b_ref"`).
2. Else NeuCodec + NeuTTS layout → **NeuTTS** multilingual /
   nano-multilingual (`voice_id` default often `"dave"` / `"paul"`).

Config keys: `voice_id`, `language` (NeuTTS multilingual).

## NeuTTS

Shipping HF repos:

| Bundle | HF repo |
|---|---|
| Multilingual | `TheStageAI/neutts-multilingual` |
| Nano multilingual | `TheStageAI/neutts-nano-multilingual` |

## Basic Usage

**Swift** — direct constructor (recommended):

```swift
import TheStageSDK

let ai = TheStageAI.shared
try await ai.initialize(apiToken: "your-api-token")

let tts = try await NeuTTSMultilingualPipeline(
    engines_path: "TheStageAI/neutts-multilingual",  // HF repo or local
    voice_id: "paul",
    language: "english"
)

let result = tts.infer(text: "Hello, world!")
let audio = result.samples           // [Float], 24 kHz mono
let sample_rate = result.sample_rate // 24000
```

**Flutter** — JSON path:

```dart
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';
import 'dart:typed_data';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

await TheStageFlutterSDK.start_model(
  model_name: 'tts',
  engines_path: 'TheStageAI/neutts-multilingual',
  config: {'voice_id': 'paul', 'language': 'english'},
);

final result = await TheStageFlutterSDK.infer(
  model_name: 'tts',
  input_json: {'text': 'Hello, world!'},
);
final audio       = result[0]['audio']       as Float32List;
final sampleRate  = result[0]['sample_rate'] as int; // 24000
```

## Inputs / Outputs

| Direction | Type | Description |
|---|---|---|
| input  `text` | `String` | Text to synthesize. |
| input  `config.temperature` | `Double?` | Sampling temperature (voice default if nil). |
| input  `config.top_k` | `Int?` | Top-k sampling (voice default if nil). |
| input  `config.seed` | `UInt64?` | Deterministic sampling. |
| input  `config.return_debug_info` | `Bool` (default `false`) | Attach decoder traces. |
| output `TTSResult.samples` | `[Float]` | 24 kHz mono PCM, samples in `[-1.0, 1.0]`. |
| output `TTSResult.sample_rate` | `Int` | Always `24000`. |
| output `TTSResult.duration` | `Double` | Seconds of audio. |
| output `TTSResult.rtf` | `Double` | Real-time factor (duration / wall time). |
| output `TTSResult.tokens_per_second` | `Double` | Decode speed. |
| output `TTSResult.debug_info` | `TTSDebugInfo?` | Only set if `return_debug_info`. |

## Sampling (voice quality)

Omit `temperature` / `top_k` / `seed` to use the **voice / bundle defaults**
(Qwen3-TTS talker is typically ~`temperature=0.9`, `top_k=50`). These knobs
are independent of streaming chunking (`TTSStreamConfig`).

| Goal | `temperature` | `top_k` | `seed` |
|---|---|---|---|
| Stable / clear (default-ish) | omit or `0.8–1.0` | omit or `40–50` | omit |
| More expressive / varied | `1.1–1.2` | `60–80` | omit |
| Safer / less artifact-prone | `0.6–0.8` | `20–30` | omit |
| Reproducible QA fixture | `0.8` | `50` | fixed (`42`) |

**Swift:**

```swift
let result = tts.infer(
    text: "Welcome to the product demo.",
    config: TTSGenerationConfig(temperature: 0.8, top_k: 30)
)

// Deterministic fixture
let fixed = tts.infer(
    text: "Hello.",
    config: TTSGenerationConfig(temperature: 0.8, top_k: 50, seed: 42)
)
```

**Flutter / JSON** (sampling keys live next to `text`):

```dart
final result = await TheStageFlutterSDK.infer(
  model_name: 'tts',
  input_json: {
    'text': 'Welcome to the product demo.',
    'temperature': 0.8,
    'top_k': 30,
  },
);
```

## Streaming

`open_streamer` is push-based: drain `streamer.output` **concurrently**
with `streamer.send(...)` so audio plays the moment each sentence is
ready. Typical use case is piping LLM tokens straight into TTS.

**Swift:**

```swift
let streamer = tts.open_streamer()

let consumer = Task {
    for await chunk in streamer.output {
        if let pcm = chunk.audio { player.enqueue(pcm) }
    }
}

streamer.send("Hello, world. ")
streamer.send("This sentence streams as it synthesizes.")
streamer.stop_stream()  // flush remaining buffer + close `output`
await consumer.value
```

If you already have the full text up-front, `infer_stream(text:)` does
the same thing in a single call.

**Flutter** — push-based streaming uses
`infer_stream` + `send` + `finish_stream` against a stable
`stream_id`. Open the stream with empty text first, then push
sentences as they become available:

```dart
const streamId = 'tts-utterance-1';
final player = TheStageAudioPlayer(sampleRate: 24000)..start();

// 1) Open the stream + start consuming chunks concurrently.
final consumer = () async {
  final stream = TheStageFlutterSDK.infer_stream(
    model_name: 'tts',
    input_json: {'text': ''},   // empty = wait for `send`
    stream_id: streamId,
  );
  await for (final chunk in stream) {
    final audio = chunk['audio'] as Float32List?;
    if (audio != null && audio.isNotEmpty) player.enqueue(audio);
    if (chunk['is_final'] == true) break;
  }
}();

// 2) Push sentences (e.g. from an LLM token stream).
await TheStageFlutterSDK.send(stream_id: streamId, text: 'Hello, world. ');
await TheStageFlutterSDK.send(
  stream_id: streamId,
  text: 'This sentence streams as it synthesizes.',
);

// 3) Signal end-of-input → flush remaining buffer, close the stream.
await TheStageFlutterSDK.finish_stream(stream_id: streamId);
await consumer;
```

For an already-known string, just call `infer_stream` with the full
`text` and skip `send` / `finish_stream`.

## Streaming Hyperparameters

`TTSStreamConfig` controls codec-side audio chunking and crossfading.
Defaults match what the SDK ships with — only override these when you
need to trade latency against smoothness.

| Field | Default | Description |
|---|---|---|
| `frames_per_chunk` | `25` | Codec frames decoded per emitted audio chunk after the first. Larger = fewer, longer chunks. |
| `first_frames_per_chunk` | `25` | Frames in the **first** chunk; pass a smaller value (or `nil` to fall back to `frames_per_chunk`) to lower time-to-first-audio. |
| `lookforward` | `5` | Future frames decoded together with each chunk to stabilise the seam (overlap-add window). |
| `lookback` | `50` | Past frames re-decoded for context when bridging chunks; reduces audible boundaries. |
| `overlap_frames` | `1` | Frames of crossfade between consecutive chunks. |

Generation knobs (`temperature`, `top_k`, …) live on `TTSGenerationConfig` and
are independent of these.

**Swift** — pass `config:` to `open_streamer` or `stream_config:` to
`infer_stream`:

```swift
let streamer = tts.open_streamer(
    config: TTSStreamConfig(
        frames_per_chunk: 25,
        first_frames_per_chunk: 12,   // smaller first chunk → faster first audio
        lookforward: 5,
        lookback: 50,
        overlap_frames: 1
    )
)

let stream = tts.infer_stream(
    text: "Hello, world.",
    stream_config: TTSStreamConfig(first_frames_per_chunk: 12)
)
```

The same knobs are exposed through the singleton:

```swift
let streamer = try ai.open_tts_streamer(
    model_name: "tts",
    config: TTSStreamConfig(first_frames_per_chunk: 12)
)
```

**Flutter** — drop a `stream_config` map into `input_json`:

```dart
final stream = TheStageFlutterSDK.infer_stream(
  model_name: 'tts',
  input_json: {
    'text': 'Hello, world.',
    'stream_config': {
      'frames_per_chunk': 25,
      'first_frames_per_chunk': 12,
      'lookforward': 5,
      'lookback': 50,
      'overlap_frames': 1,
    },
  },
);
```

Unknown keys are ignored; defaults are kept for any field you omit.

## Voices and Languages

Voices live under `voices/{voice_id}/` inside the bundle. The
multilingual model supports:

`english`, `french`, `german`, `spanish`, `portuguese`, `japanese`,
`korean`, `chinese`, `urdu`

Pass the language at construction time (it can be overridden per-bundle
default). The Nano variant is English-only and ignores the parameter.

## Audio Output

- 24 kHz mono `[Float]`, samples in `[-1.0, 1.0]`.
- **Batch:** `TTSResult.samples` is the full utterance.
- **Streaming:** each `InferenceStreamChunk.audio` is one sentence-sized
  PCM slice; `chunk.sample_rate` is `24000`. The streamer applies
  overlap-add crossfading between sentences, so consumers can
  concatenate slices end-to-end.
- If your playback path runs at 16 kHz to match VAD/ASR, resample TTS
  output down to 16 kHz, or drive your `AudioStreamPlayer` /
  `TheStageAudioPlayer` at 24 kHz (the bundled players default to
  24 kHz).

See [Audio I/O Contract](./README.md#audio-io-contract) for the
shared format used across VAD / ASR / TTS.

## Singleton API (`TheStageAI.shared`)

```swift
try await ai.start_model(
    model_name: "tts",
    engines_path: "TheStageAI/neutts-multilingual",
    config: ["voice_id": "paul", "language": "english"]
)

let json = try ai.infer(
    model_name: "tts",
    input_json: [
        "text": "Hello, world!",
        "temperature": 1.0,            // optional
        "top_k": 50                    // optional
    ]
)
let audio = json[0]["audio"] as! [Float]
```

JSON response keys: `audio` (`[Float]`), `sample_rate` (`Int`),
`duration` (`Double`), `tokens_per_second` (`Double`), `rtf`
(`Double`), `debug_info` (only when requested).

JSON streaming yields typed `InferenceStreamChunk` values; PCM samples
live on `chunk.audio`:

```swift
let stream = try ai.infer_stream(
    model_name: "tts",
    input_json: ["text": "A long paragraph of text to speak."]
)

for await chunk in stream {
    if let audio = chunk.audio, !audio.isEmpty {
        play(audio, sampleRate: chunk.sample_rate ?? 24000)
    }
    if chunk.is_final { break }
}
```

A push-based streamer is also reachable via the singleton:

```swift
let streamer = try ai.open_tts_streamer(model_name: "tts")
// same `streamer.send(...)` / `streamer.stop_stream()` shape as above
```

The Flutter `TheStageFlutterSDK.infer` / `infer_stream` calls hit this
exact JSON path, so the response keys above apply unchanged on Dart.
PCM audio crosses the platform channel as `Float32List`; do not
promote to `Float64List`.

## Full Constructor

```swift
let tts = try await NeuTTSMultilingualPipeline(
    engines_path: "TheStageAI/neutts-multilingual",
    voice_id: "paul",                // voice subfolder under voices/
    language: "english",             // optional language override
    device: "npu",                   // "npu" | "gpu" | "cpu"
    devices: nil,                    // optional per-component override
    on_load_progress: nil            // see "Load Progress" below
)

```

`TheStageAI.shared.initialize(apiToken:)` must have succeeded before
the call returns.

## Load Progress

`on_load_progress` is **optional**. When set, the handler fires through
four phases with a monotonic `fraction` in `0...1`:

```swift
let tts = try await NeuTTSMultilingualPipeline(
    engines_path: "TheStageAI/neutts-multilingual",
    voice_id: "paul",
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
  if (event['model_name'] != 'tts') return;
  final phase    = event['phase']    as String?;   // downloading | extracting | loading | ready
  final fraction = event['progress'] as double?;   // 0.0 ... 1.0, monotonic
  print('[tts] $phase ${(fraction ?? 0) * 100}%');
});

await TheStageFlutterSDK.start_model(
  model_name: 'tts',
  engines_path: 'TheStageAI/neutts-multilingual',
  config: {'voice_id': 'paul', 'language': 'english'},
);
```

## Prefetch Engines

```swift
let engines_dir = try await ai.prefetch_engines(
    repo_id: "TheStageAI/neutts-multilingual"
)

// Later — instant load, no network:
let tts = try await NeuTTSMultilingualPipeline(
    engines_path: engines_dir,
    voice_id: "paul"
)
```

## Cleanup

`NeuTTSMultilingualPipeline` and `Qwen3TTSPipeline` are normal Swift
objects — drop the reference to release them. When you used the
singleton API:

```swift
_ = try ai.stop_model(model_name: "tts")
```

**Flutter:**

```dart
await TheStageFlutterSDK.stop_model(model_name: 'tts');
```

## Agent checklist

- Output is always **24 kHz** mono Float / `Float32List`.
- `start_model` auto-routes Qwen3-TTS vs NeuTTS from the bundle layout.
- Qwen3 default `voice_id`: `b_ref`. NeuTTS examples often use `paul` / `dave`.
- Streaming: drain `infer_stream` / streamer `output` concurrently with `send`.
