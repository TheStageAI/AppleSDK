# TTS (Text-to-Speech)

On-device neural text-to-speech that produces 24 kHz mono float PCM you
can play, save, or stream. Two families live behind the same voice /
config API:

- **`NeuTTSMultilingualPipeline`** — NeuTTS multilingual / nano
- **`Qwen3TTSPipeline`** — Qwen3-TTS (12 Hz talker + MTP + codec)

Flutter / `start_model` auto-routes Qwen3-TTS vs NeuTTS from the bundle
layout — Dart callers only see a `tts` model handle. All surfaces share
the same on-disk cache and the same output contract; the codec is
always 24 kHz and the pipeline optionally resamples on the way out.

> **Main features**
>
> - **Two families, one API**: `NeuTTSMultilingualPipeline` and
>   `Qwen3TTSPipeline` both extend `TheStageTTSPipeline`; the same
>   `infer` / `infer_stream` / `open_streamer` / `set_voice` calls work
>   on either.
> - **24 kHz mono float PCM out**: hand off to `AudioStreamPlayer` /
>   `TheStageAudioPlayer`, write to a WAV, or resample once via
>   `TTSGenerationConfig.sample_rate_out` (16 / 24 / 48 kHz are
>   typical).
> - **Push streamer**: call `send(_:)` with partial text (LLM deltas,
>   chat tokens) and drain PCM from `streamer.output` before the full
>   sentence is even done.
> - **Three voice knobs that compose**: bundle voice id, external
>   prepared pack (`voice_dir`), and NeuTTS multilingual language
>   override. Same names on the constructor and on
>   `set_voice(voice_dir:voice_id:language:)`.
> - **Runtime voice hot-swap**: no engine reload, no bundle re-download.
> - **Auto-routing**: Flutter `start_model("tts")` picks the family from
>   the engine bundle layout; Dart callers only see one `tts` handle.
> - **NeuTTS multilingual**: english, french, german, spanish,
>   portuguese, japanese, korean, chinese, urdu — same speaker across
>   languages.

## In this page

Here we will cover the following topics:

- [**Supported models**](#supported-models): models, languages, default voices.
- [**API surface**](#api-surface): Swift constructor / Flutter singleton, batch and streaming.
- [**Quick start**](#quick-start): one-shot NeuTTS to PCM and push-streamer Qwen3-TTS.
- [**Configuration**](#configuration): `TTSGenerationConfig` sampling recipes as runnable code, plus `TTSStreamConfig` chunking knobs.
- [**Output contract**](#output-contract): the shape of `TTSResult` and every streamer chunk.
- [**Lifecycle**](#lifecycle): initialize → construct → infer / stream → cleanup.
- [**Usage Guides**](#usage-guides): play through the audio engine, change output kHz, save to WAV, speak text, stream early audio, pipe LLM tokens, pick a voice / language / pack, produce a `voice_dir`, clarity, reproducible QA.
- [**Troubleshooting**](#troubleshooting): empty audio, choppy streaming, wrong language, slow first audio, playback-rate mismatch, missing voice.

## Supported models

| Model | HF repo | Family | Device | Output | Fleet pin |
|-------|---------|--------|--------|--------|-----------|
| NeuTTS nano multilingual | `TheStageAI/neutts-nano-multilingual` | NeuTTS | NPU | 24 kHz mono | v1.1 |
| NeuTTS multilingual | `TheStageAI/neutts-multilingual` | NeuTTS | NPU | 24 kHz mono | temporarily out of v1.1 |
| Qwen3-TTS 12 Hz 0.6B | `TheStageAI/Qwen3-TTS-12Hz-0.6B-Base` | Qwen3 | NPU | 24 kHz mono | v1.1 |

**Voice API (both families):** pick a bundle voice with `voice_id`, or an
external prepared pack with `voice_dir`. Hot-swap with
`set_voice(voice_dir:voice_id:language:)` without reloading engines.
Same keys work on `start_model` config.

NeuTTS languages: english, french, german, spanish, portuguese,
japanese, korean, chinese, urdu. Typical NeuTTS voices: `paul`, `dave`.
Qwen3 default voice id: `b_ref`.

## API surface

| Purpose | Swift | Flutter |
|---------|-------|---------|
| Init (NeuTTS) | `try await NeuTTSMultilingualPipeline(engines_path:voice_id:voice_dir:language:device:)` | `start_model(model_name:"tts", engines_path:, config: ["voice_id":, "voice_dir":, "language":])` |
| Init (Qwen3) | `try await Qwen3TTSPipeline(engines_path:voice_id:voice_dir:device:)` | same `start_model` — auto-routed |
| One-shot | `tts.infer(text:config:)` → `TTSResult` | `infer(model_name:"tts", input_json:)` |
| Streaming | `tts.infer_stream(text:config:)` or `tts.open_streamer(config:)` | `open_tts_streamer(model_name:"tts", config:)` |
| Voice hot-swap | `tts.set_voice(voice_dir:voice_id:language:)` | `set_voice_for(model_name:"tts", …)` |
| Progress | `on_load_progress` | `TheStageFlutterSDK.on_progress` |
| Cleanup | drop the pipeline | `stop_model(model_name:"tts")` |

## Quick start

**Swift — NeuTTS one-shot to PCM:**

```swift
import TheStageSDK

try await TheStageAI.shared.initialize(apiToken: "your-api-token")

let tts = try await NeuTTSMultilingualPipeline(
    engines_path: "TheStageAI/neutts-nano-multilingual",
    voice_id: "dave",
    language: "english",
    device: "npu"
)

var config = TTSGenerationConfig()
config.sample_rate_out = 24_000

let result = try tts.infer(text: "Hello from TheStage TTS.", config: config)
// result.samples : [Float] mono, result.sample_rate == 24000
```

**Swift — Qwen3-TTS streaming with a push streamer:**

```swift
let tts = try await Qwen3TTSPipeline(
    engines_path: "TheStageAI/Qwen3-TTS-12Hz-0.6B-Base",
    voice_id: "b_ref",
    device: "npu"
)

let streamer = tts.open_streamer(config: TTSStreamConfig())

let consumer = Task {
    for await chunk in streamer.output {
        // 24 kHz mono Float PCM; hand off to your player.
        if let pcm = chunk.audio { speaker.append(pcm) }
    }
}

streamer.send("This is a streamed sentence.")
streamer.stop_stream()   // no more input; drain remaining audio
await consumer.value
```

The streamer is push-based: `send(_:)` for text (any size, no need
to buffer whole sentences), then `stop_stream()` when the producer is
done. The `output` stream drains until all audio is emitted.

**Flutter:**

```dart
await TheStageFlutterSDK.initialize(api_token: 'your-api-token');
await TheStageFlutterSDK.start_model(
  model_name: 'tts',
  engines_path: 'TheStageAI/neutts-nano-multilingual',
  config: {'voice_id': 'dave', 'language': 'english'},
);

final out = await TheStageFlutterSDK.infer(
  model_name: 'tts',
  input_json: {'text': 'Hello from Flutter.', 'sample_rate_out': 24000},
);
final pcm = out[0]['audio'] as List<double>;
```

## Configuration

`TTSGenerationConfig` controls sampling / voice; `TTSStreamConfig`
controls chunking. Omit to use pack / voice defaults.

**Sampling recipes.** All four call the same `tts.infer(text:config:)`
— only `TTSGenerationConfig` changes. Copy the block that matches
the product job and tune on device.

*1. Stable / clear (product default — most demos start here):*

```swift
var config = TTSGenerationConfig()
config.temperature = 0.9   // omit for pack default
config.top_k = 45
let result = try tts.infer(text: "Welcome to the product demo.", config: config)
```

*2. More expressive (character voice, animation, playful TTS):*

```swift
var config = TTSGenerationConfig()
config.temperature = 1.15
config.top_k = 70
let result = try tts.infer(text: "Oh WOW! You'll never guess what happened.", config: config)
```

*3. Safer / fewer artifacts (long-form narration, audiobook segments):*

```swift
var config = TTSGenerationConfig()
config.temperature = 0.7
config.top_k = 25
let result = try tts.infer(text: "Chapter one. The old lighthouse …", config: config)
```

*4. Reproducible QA (goldens / regression tests):*

```swift
var config = TTSGenerationConfig()
config.temperature = 0.8
config.top_k = 50
config.seed = 42                       // same seed → same PCM per device+bundle
let result = try tts.infer(text: "Hello! This is a TheStage text to speech demo.", config: config)
```

Other fields on `TTSGenerationConfig`:

| Field | Meaning |
|-------|---------|
| `sample_rate_out` | Optional resample after codec (native is 24000) |
| `return_debug_info` | Attach decoder traces |

Flutter/JSON also accepts `sample_rate_out_khz` (16 / 24 / 48).

**Stream chunking (`TTSStreamConfig`):**

| Field | Default | Notes |
|-------|---------|-------|
| `frames_per_chunk` | 25 | Frames per chunk after the first |
| `first_frames_per_chunk` | 25 | First chunk size; smaller → faster TTFA |
| `lookforward` | 5 | Future frames for seams |
| `lookback` | 50 | Past frames when bridging |
| `overlap_frames` | 1 | Crossfade frames |

## Output contract

Mono float PCM in `[-1, 1]`. The codec is native 24 kHz; if you set
`sample_rate_out` it is polyphase-resampled to that rate before the
result / chunk is returned. Voice Agent has its own `sample_rate_out`
at the audio engine — standalone TTS resampling and the agent's
playback resampler are independent.

| Field | Meaning |
|-------|---------|
| `samples` / `audio` | PCM buffer (Swift `[Float]` / JSON list) |
| `sample_rate` | Output Hz (24000 or `sample_rate_out`) |
| `duration` | Seconds of audio |
| `rtf` | Real-time factor |
| `tokens_per_second` | Decode speed |
| `debug_info` | Only when `return_debug_info` is set |

See [Audio I/O Contract](./README.md#audio-io-contract).

## Lifecycle

1. `initialize(apiToken:)` once per process.
2. Construct a pipeline or `start_model` — first call downloads and
   compiles the pack.
3. Call `infer` / `infer_stream` / `open_streamer`. Swap voices with
   `set_voice(...)` — no engine reload.
4. Drop the pipeline (Swift) or `stop_model` (Flutter) when done.

## Usage Guides

Jump to a recipe:

- [How do I save PCM to a WAV on disk?](#how-do-i-save-pcm-to-a-wav-on-disk)
- [How do I play PCM through the audio engine?](#how-do-i-play-pcm-through-the-audio-engine)
- [How do I change the output sample rate (kHz)?](#how-do-i-change-the-output-sample-rate-khz)
- [How do I speak a string of text?](#how-do-i-speak-a-string-of-text)
- [How do I hear audio before the sentence finishes?](#how-do-i-hear-audio-before-the-sentence-finishes)
- [How do I pipe LLM tokens into TTS?](#how-do-i-pipe-llm-tokens-into-tts)
- [How do I change voice / language / clone a speaker?](#how-do-i-change-voice-language-clone-a-speaker)
- [How do I produce a `voice_dir` (voice pack)?](#how-do-i-produce-a-voice-dir-voice-pack)
- [Why is playback too fast or too slow?](#why-is-playback-too-fast-or-too-slow)
- [How do I get clearer speech / faster first audio?](#how-do-i-get-clearer-speech-faster-first-audio)
- [How do I get reproducible QA audio?](#how-do-i-get-reproducible-qa-audio)

### How do I save PCM to a WAV on disk?

Default is **24 kHz** mono Float. Write with `AudioIO.write_wav`:

```swift
let result: TTSResult = tts.infer(
    text: "Hello from TheStage.",
    config: TTSGenerationConfig(sample_rate_out: 48_000)
)
let samples: [Float] = result.samples          // mono, [-1, 1]
let sample_rate: Int = result.sample_rate       // 48000
try AudioIO.write_wav(
    samples: samples,
    sample_rate: sample_rate,
    path: "/tmp/tts_out.wav"
)
```

### How do I play PCM through the audio engine?

The SDK ships a low-latency player for exactly this PCM:
`AudioStreamPlayer` (Swift) / `TheStageAudioPlayer` (Flutter). Match
the player sample rate to `result.sample_rate` (or to the
`sample_rate_out` you requested).

**Swift — one-shot infer → speaker**

```swift
import TheStageSDK

try await TheStageAI.shared.initialize(apiToken: "your-api-token")

let tts = try await NeuTTSMultilingualPipeline(
    engines_path: "TheStageAI/neutts-nano-multilingual",
    voice_id: "dave",
    language: "english",
    device: "npu"
)

let result = tts.infer(text: "Hello from TheStage.")
// result.sample_rate is 24000 unless you set sample_rate_out

let player = AudioStreamPlayer(
    config: AudioStreamConfig(sample_rate: Double(result.sample_rate))
)
player.start()
player.enqueue(result.samples)   // mono Float in [-1, 1]
await player.drain()             // wait until the buffer finishes
player.stop()
```

**Swift — streamer → speaker (first audio before the sentence ends)**

```swift
let player = AudioStreamPlayer(
    config: AudioStreamConfig(sample_rate: 24_000)
)
player.start()

let streamer = tts.open_streamer()
let consumer = Task {
    for await chunk in streamer.output {
        if let pcm = chunk.audio { player.enqueue(pcm) }
    }
}

streamer.send("Hello from TheStage. ")
streamer.send("This plays as it synthesizes.")
streamer.stop_stream()
await consumer.value
await player.drain()
player.stop()
```

**Flutter — one-shot infer → speaker**

```dart
import 'dart:typed_data';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');
await TheStageFlutterSDK.start_model(
  model_name: 'tts',
  engines_path: 'TheStageAI/neutts-nano-multilingual',
  config: {'voice_id': 'dave', 'language': 'english'},
);

final result = await TheStageFlutterSDK.infer(
  model_name: 'tts',
  input_json: {'text': 'Hello from TheStage.'},
);
final audio = result[0]['audio'] as Float32List;
final sampleRate = result[0]['sample_rate'] as int; // 24000

final player = TheStageAudioPlayer(sampleRate: sampleRate);
await player.start();
player.enqueue(audio);
await player.drain();
await player.stop();
```

Voice Agent owns its own `AudioEngineNode` speaker path — you do not
wire `AudioStreamPlayer` yourself inside the agent. Use this recipe for
standalone TTS UIs.

### How do I change the output sample rate (kHz)?

The codec is always **24 kHz**. Set `TTSGenerationConfig.sample_rate_out`
(Hz) to resample once on the way out — typical targets are 16 / 24 /
48 kHz. Then point the player at the **same** rate.

**Swift**

```swift
// Speak at 48 kHz to match a 48 kHz AVAudioSession / device graph
var config = TTSGenerationConfig()
config.sample_rate_out = 48_000

let result = tts.infer(text: "Forty eight kilohertz output.", config: config)
assert(result.sample_rate == 48_000)

let player = AudioStreamPlayer(
    config: AudioStreamConfig(sample_rate: 48_000)
)
player.start()
player.enqueue(result.samples)
await player.drain()
player.stop()
```

Other common targets:

```swift
config.sample_rate_out = 16_000   // match Whisper / ASR graphs
config.sample_rate_out = 24_000   // codec-native (same as omitting)
config.sample_rate_out = 48_000   // match many iOS sessions
```

**Flutter** — Hz via `sample_rate_out`, or kHz via `sample_rate_out_khz`:

```dart
final result = await TheStageFlutterSDK.infer(
  model_name: 'tts',
  input_json: {
    'text': 'Forty eight kilohertz output.',
    'sample_rate_out': 48000,       // Hz
    // 'sample_rate_out_khz': 48,   // equivalent shorthand
  },
);
final sampleRate = result[0]['sample_rate'] as int; // 48000
final player = TheStageAudioPlayer(sampleRate: sampleRate)..start();
player.enqueue(result[0]['audio'] as Float32List);
await player.drain();
await player.stop();
```

Omit `sample_rate_out` to keep codec-native 24 kHz. Inside the Voice
Agent, speaker rate is `TheStageAgentConfig.sample_rate_out` — that
resampler is independent of standalone TTS
`TTSGenerationConfig.sample_rate_out`.

### How do I speak a string of text?

Batch `infer` when you already have the full string and do not need
first-audio latency.

**Shared demo text:**

```text
Hello! This is a TheStage text to speech demo.
```

| Family | Voice | Artifact | Duration | Rate | rtf (audio/wall) |
|---|---|---|---|---|---|
| NeuTTS | `dave` | [`assets/tts_neutts_nano.wav`](./assets/tts_neutts_nano.wav) | ~3.34 s | 24000 Hz | ~2.62 |
| Qwen3-TTS | `b_ref` | [`assets/tts_qwen3.wav`](./assets/tts_qwen3.wav) | ~5.68 s | 24000 Hz | ~1.47 |

**Swift — NeuTTS:**

```swift
import TheStageSDK

try await TheStageAI.shared.initialize(apiToken: "your-api-token")

let tts = try await NeuTTSMultilingualPipeline(
    engines_path: "TheStageAI/neutts-nano-multilingual",
    voice_id: "dave",
    language: "english",
    device: "npu"
)

let result: TTSResult = tts.infer(
    text: "Hello! This is a TheStage text to speech demo."
)
let samples: [Float] = result.samples
let sample_rate: Int = result.sample_rate  // 24000
// play with a 24 kHz player — see assets/tts_neutts_nano.wav
```

**Swift — Qwen3-TTS:**

```swift
let tts = try await Qwen3TTSPipeline(
    engines_path: "TheStageAI/Qwen3-TTS-12Hz-0.6B-Base",
    voice_id: "b_ref",
    device: "npu"
)
let result: TTSResult = tts.infer(
    text: "Hello! This is a TheStage text to speech demo."
)
let samples: [Float] = result.samples  // 24 kHz mono
// see assets/tts_qwen3.wav
```

**Flutter** (auto-routes from `engines_path`):

```dart
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';
import 'dart:typed_data';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

await TheStageFlutterSDK.start_model(
  model_name: 'tts',
  engines_path: 'TheStageAI/neutts-nano-multilingual',
  config: {'voice_id': 'dave', 'language': 'english'},
);

final result = await TheStageFlutterSDK.infer(
  model_name: 'tts',
  input_json: {
    'text': 'Hello! This is a TheStage text to speech demo.',
  },
);
final audio = result[0]['audio'] as Float32List;
final sampleRate = result[0]['sample_rate'] as int; // 24000
```

For Qwen3 on Flutter, pass
`engines_path: 'TheStageAI/Qwen3-TTS-12Hz-0.6B-Base'` and
`config: {'voice_id': 'b_ref'}`.

### How do I hear audio before the sentence finishes?

Use the push streamer and **drain `output` concurrently** with `send`.
If you send all text before reading chunks, buffers stall. Wire chunks
into `AudioStreamPlayer` / `TheStageAudioPlayer` (see
[How do I play PCM through the audio engine?](#how-do-i-play-pcm-through-the-audio-engine)).

**Swift:**

```swift
let player = AudioStreamPlayer(config: AudioStreamConfig(sample_rate: 24_000))
player.start()

let streamer = tts.open_streamer()
let consumer = Task {
    for await chunk in streamer.output {
        if let pcm = chunk.audio { player.enqueue(pcm) }
    }
}

streamer.send("Hello, world. ")
streamer.send("This sentence streams as it synthesizes.")
streamer.stop_stream()
await consumer.value
await player.drain()
player.stop()
```

Full text already known → `infer_stream(text:)` in one call.

**Flutter** — open with empty text, then `send` / `finish_stream`:

```dart
const streamId = 'tts-utterance-1';
final player = TheStageAudioPlayer(sampleRate: 24000);
await player.start();

final consumer = () async {
  final stream = TheStageFlutterSDK.infer_stream(
    model_name: 'tts',
    input_json: {'text': ''},
    stream_id: streamId,
  );
  await for (final chunk in stream) {
    final audio = chunk['audio'] as Float32List?;
    if (audio != null && audio.isNotEmpty) player.enqueue(audio);
    if (chunk['is_final'] == true) break;
  }
}();

await TheStageFlutterSDK.send(stream_id: streamId, text: 'Hello, world. ');
await TheStageFlutterSDK.send(
  stream_id: streamId,
  text: 'This sentence streams as it synthesizes.',
);
await TheStageFlutterSDK.finish_stream(stream_id: streamId);
await consumer;
await player.drain();
await player.stop();
```

Start the consumer **before** the first `send`.

### How do I pipe LLM tokens into TTS?

Push tokens (or deltas) into the same streamer. Sentence segmentation
happens inside TTS — you do not wait for full sentences in the LLM node.

**Swift:**

```swift
let streamer = tts.open_streamer()
let consumer = Task {
    for await chunk in streamer.output {
        if let pcm = chunk.audio { player.enqueue(pcm) }
    }
}

for await chunk in llm.infer_stream(prompt: user_query, config: config) {
    // TheStageLLM → LLMStreamChunk.text (not .delta)
    if !chunk.is_final, !chunk.text.isEmpty {
        streamer.send(chunk.text)
    }
}
streamer.stop_stream()
await consumer.value
```

**Flutter / singleton:** `infer_stream` chunks use **`delta`** — `send`
each non-empty `delta`, then `finish_stream`.

For the full mic → ASR → LLM → TTS loop, prefer the
[Voice Agent](./voice_agent.md).

### How do I change voice / language / clone a speaker?

Both TTS families (`NeuTTSMultilingualPipeline` and `Qwen3TTSPipeline`)
share one voice API on the base `TheStageTTSPipeline`. Three knobs
compose:

1. **Bundle voice by id** (`voice_id`) — pick a speaker that ships
   inside the pack under `voices/<id>/`. NeuTTS ships `paul`, `dave`,
   `jo`; Qwen3-TTS ships `b_ref`.
2. **External prepared pack** (`voice_dir`) — point the pipeline at a
   folder you produced with the voice-prep tools (`voice.json` /
   `VoiceSpec` on disk). Takes precedence over `voice_id`.
3. **Language override** (`language`) — NeuTTS multilingual selects the
   same speaker in a different language (english / french / german /
   spanish / portuguese / japanese / korean / chinese / urdu). Ignored
   by Qwen3 unless the pack shipped with per-language variants.

The same three names appear on the constructor and on
`set_voice(voice_dir:voice_id:language:)` — nothing new to learn at
runtime.

**Config-time (load with the right voice already selected)**

```swift
import TheStageSDK

try await TheStageAI.shared.initialize(apiToken: "your-api-token")

// (a) bundle voice — the common case.
let neutts = try await NeuTTSMultilingualPipeline(
    engines_path: "TheStageAI/neutts-nano-multilingual",
    voice_id: "dave",
    language: "english",
    device: "npu"
)

// (b) external prepared pack — voice_dir wins over voice_id.
let qwen3 = try await Qwen3TTSPipeline(
    engines_path: "TheStageAI/Qwen3-TTS-12Hz-0.6B-Base",
    voice_id: "b_ref",                                 // fallback / cosmetic
    voice_dir: "/Library/Application Support/MyApp/voices/tutor_dave",
    device: "npu"
)
```

**Runtime hot-swap (no engine reload)**

`set_voice(voice_dir:voice_id:language:)` swaps the active voice on a
live pipeline without touching the compiled engines. Pass any subset —
`nil` fields keep their current value.

```swift
// Bundle voice, different speaker.
try tts.set_voice(voice_id: "paul")

// Same speaker, different language (NeuTTS multilingual).
try tts.set_voice(voice_id: "paul", language: "french")

// Point at an external prepared pack the user just downloaded.
try tts.set_voice(voice_dir: prepared_pack_url.path)

// Clear the external pack — falls back to voice_id.
try tts.set_voice(voice_dir: "")
```

**Flutter (`start_model` config keys mirror the Swift names)**

```dart
await TheStageFlutterSDK.start_model(
  model_name: 'tts',
  engines_path: 'TheStageAI/Qwen3-TTS-12Hz-0.6B-Base',
  config: {
    'voice_id': 'b_ref',                       // bundle id
    'voice_dir': '/path/to/prepared_pack',     // external pack (optional)
    'language': 'french',                      // NeuTTS multilingual override
  },
);
```

Inside the Voice Agent the same knobs are exposed as `tts_voice`,
`tts_voice_dir`, `tts_language` on `TheStageAgentConfig` — see
[voice agent](./voice_agent.md#how-do-i-pick-a-tts-voice-in-the-agent).

### How do I produce a `voice_dir` (voice pack)?

A voice pack is just a folder with a `voice.json` (schema:
`VoiceSpec`) plus the reference material the codec needs. There are
two ways to get one:

1. **Download a prepared pack** — e.g. Qwen3-TTS tutor voices from HF
   (`TheStageAI/Qwen3-TTS-Tutor-VoicePacks`). Extract into your app's
   Application Support directory and point `voice_dir` at the
   folder. See [`Qwen3-TTS-Tutor-VoicePacks`](./hf_cards/Qwen3-TTS-Tutor-VoicePacks/README.md).
2. **Prepare one yourself** from a reference clip using the voice-prep
   scripts under `(SDK internals)` — the produced folder has the
   same shape.

```text
tutor_dave/
├── voice.json        # VoiceSpec — ids, tokens, refs
├── reference.wav     # 24 kHz mono reference clip
└── …                 # codec-specific side files
```

The pipeline validates `voice.json` at load time; a bad or missing
file throws before the first `infer`.

### Why is playback too fast or too slow?

Wrong speed almost always means the **player rate ≠ `result.sample_rate`**.

1. Match `AVAudioPlayerNode` / `TheStageAudioPlayer` to `result.sample_rate`.
2. Or set `TTSGenerationConfig.sample_rate_out` (Hz) so `infer` /
   `infer_stream` emit at your session rate (polyphase resample).
3. In the Voice Agent, set `sample_rate_out` to the playback rate you
   want — the agent resamples TTS internally (`tts_sample_rate` stays
   24000; mic path stays `sample_rate_in` 16000).

### How do I get clearer speech / faster first audio?

**Clarity / stability** — sampling:

```swift
let result = tts.infer(
    text: "Welcome to the product demo.",
    config: TTSGenerationConfig(temperature: 0.8, top_k: 30)
)
```

**Faster time-to-first-audio** — streaming chunking (voice-assistant
recipe: `first_frames_per_chunk` ≈ 6–12):

```swift
let streamer = tts.open_streamer(
    config: TTSStreamConfig(
        frames_per_chunk: 25,
        first_frames_per_chunk: 12,
        lookforward: 5,
        lookback: 50,
        overlap_frames: 1
    )
)
```

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

Raise `overlap_frames` to 2–3 if you hear clicks at chunk seams.

### How do I get reproducible QA audio?

Fix `seed` (+ optional temperature/top_k) with the same text, bundle,
and device:

```swift
let fixed = tts.infer(
    text: "Hello! This is a TheStage text to speech demo.",
    config: TTSGenerationConfig(temperature: 0.8, top_k: 50, seed: 42)
)
print(fixed.duration, fixed.sample_rate, fixed.rtf)
```

Same-device reproducibility only — do not expect bit-identical PCM
across OS / chip revisions.

## Troubleshooting

### Empty `samples` / no audio

1. Non-empty `text` (not whitespace-only).
2. `voice_id` must exist under `voices/` (or a valid `voice_dir`).
3. `return_debug_info: true` and inspect `debug_info`.
4. Confirm `start_model` / constructor finished before `infer`.

### Choppy or robotic streaming

1. Keep `overlap_frames >= 1`.
2. Drain `output` **concurrently** with `send` — never after all text.
3. Try larger `frames_per_chunk` if individual chunks sound thin.

### Wrong language pronunciation (NeuTTS)

Set `language` to match the text (e.g. `"french"`). Default English
phonemization mangles other languages.

### High latency before first audio

1. Prefer streaming over batch `infer`.
2. Lower `first_frames_per_chunk` (6–12).
3. `prefetch_engines` so the first load is local-only.

### Playback wrong speed

Player not at 24000 Hz. Fix the player, resample, or use agent
`sample_rate_out`.

### Unknown / missing voice

Confirm the voice folder exists in the cached bundle. espeak English
nano (`TheStageAI/neutts`) is **not** in the current fleet — use
`neutts-nano-multilingual` or Qwen3-TTS.

## Load Progress / Prefetch / Cleanup

### Load progress

```swift
let tts = try await NeuTTSMultilingualPipeline(
    engines_path: "TheStageAI/neutts-nano-multilingual",
    voice_id: "dave",
    on_load_progress: { p in
        print("[\(p.model)] \(p.phase) \(Int(p.fraction * 100))%")
    }
)
```

Same on `start_model` / `prefetch_engines`. See
[Load Progress](./README.md#load-progress).

**Flutter:**

```dart
TheStageFlutterSDK.on_progress.listen((event) {
  if (event['model_name'] != 'tts') return;
  final phase = event['phase'] as String?;
  final fraction = event['progress'] as double?;
  print('[tts] $phase ${(fraction ?? 0) * 100}%');
});

await TheStageFlutterSDK.start_model(
  model_name: 'tts',
  engines_path: 'TheStageAI/neutts-nano-multilingual',
  config: {'voice_id': 'dave', 'language': 'english'},
);
```

### Prefetch

```swift
let engines_dir = try await ai.prefetch_engines(
    repo_id: "TheStageAI/neutts-nano-multilingual"
)
let tts = try await NeuTTSMultilingualPipeline(
    engines_path: engines_dir,
    voice_id: "dave"
)
```

### Cleanup

Drop the pipeline reference, or:

```swift
_ = try ai.stop_model(model_name: "tts")
```

```dart
await TheStageFlutterSDK.stop_model(model_name: 'tts');
```
