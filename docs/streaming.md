# Streaming

Real-time streaming inference for TTS and LLM pipelines.

---

## TTS Streaming

Yields audio chunks as sentences are synthesized — much lower time-to-first-audio than batch mode.

### Swift — Simple Consumer

```swift
import TheStageSDK

let ai = TheStageAI.shared
try await ai.initialize(apiToken: "your_api_token")

try await ai.start_model(
    model_name: "tts",
    engines_path: "TheStageAI/neutts-multilingual",
    config: ["voice_id": "dave"],
    revision: "develop"
)

let stream = try ai.infer_stream(
    model_name: "tts",
    input_json: ["text": "A long paragraph of text to speak aloud."]
)

for await chunk in stream {
    guard let audio = chunk.audio else { continue }
    play_audio(audio, sample_rate: chunk.sample_rate ?? 24000)

    if chunk.is_final {
        print("Decode tokens: \(chunk.generated_tokens ?? 0)")
        print("Tok/s: \(chunk.tokens_per_second ?? 0)")
        print("First chunk: \(chunk.time_to_first_token ?? 0)s")
        print("Total wall-clock: \(chunk.total_seconds ?? 0)s")
    }
}
```

### Swift — Producer / Consumer with AudioStreamPlayer

Two concurrent tasks: one drives TTS inference, the other plays audio
as chunks arrive. This is the recommended pattern for low-latency playback.

```swift
import TheStageSDK

let ai = TheStageAI.shared
try await ai.start_model(
    model_name: "tts",
    engines_path: "TheStageAI/neutts-multilingual",
    config: ["voice_id": "paul"]
)

let player = AudioStreamPlayer(
    config: AudioStreamConfig(
        sample_rate: 24000,
        channels: 1,
        buffer_size: 512
    )
)
player.start()

let stream = try ai.infer_stream(
    model_name: "tts",
    input_json: ["text": "Hello! This is a streaming demo with real-time audio."]
)

for await chunk in stream {
    guard let audio = chunk.audio, !audio.isEmpty else { continue }
    player.enqueue(audio)
}

await player.drain()
player.stop()
```

### AudioStreamConfig Options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `sample_rate` | `Double` | 24000 | Audio sample rate in Hz |
| `channels` | `UInt32` | 1 | Number of audio channels |
| `buffer_size` | `UInt32` | 512 | I/O buffer size (iOS only) |
| `category` | `AVAudioSession.Category` | `.playback` | Audio session category (iOS only) |
| `mode` | `AVAudioSession.Mode` | `.default` | Audio session mode (iOS only) |

### Swift — Push-Based (LLM → TTS)

Feed text incrementally as it arrives from another model. The streamer
splits sentences internally and produces audio as complete sentences are
ready. Use `TheStageAI.shared.open_tts_streamer(model_name:)` to pull a
fresh streamer per turn — there is no need (or way) to construct
`TTSStreamer` directly from outside the SDK module.

```swift
import TheStageSDK

let ai = TheStageAI.shared

try await ai.start_model(
    model_name: "llm",
    engines_path: "TheStageAI/Qwen3-0.6B"
)
try await ai.start_model(
    model_name: "tts",
    engines_path: "TheStageAI/neutts-multilingual",
    config: ["voice_id": "dave"]
)

let player = AudioStreamPlayer(sample_rate: 24000)
player.start()

let streamer = try ai.open_tts_streamer(model_name: "tts")

// Audio consumer task
Task {
    for await chunk in streamer.output {
        if let pcm = chunk.audio, !pcm.isEmpty {
            player.enqueue(pcm)
        }
    }
    await player.drain()
    player.stop()
}

// LLM → TTS producer
let llm_stream = try ai.infer_stream(
    model_name: "llm",
    input_json: [
        "prompt": "Tell me a joke",
        "max_new_tokens": 256
    ]
)

for await chunk in llm_stream {
    if let delta = chunk.delta, !delta.isEmpty {
        streamer.send(delta)
    }
    if chunk.is_final {
        streamer.stop_stream()   // flush tail + close output cleanly
    }
}
```

`streamer.stop_stream()` flushes any partial sentence buffered inside
the splitter before closing the output stream. Use `streamer.cancel()`
instead if you want to abort an in-flight turn (e.g. on barge-in) —
that drops the buffer and closes immediately.

This is exactly what `TheStageVoiceAgent` does internally: its
`TTSNode` opens one `TTSStreamingSession` (backed by a `TTSStreamer`)
per turn, pumps LLM deltas straight in, and `cancel()`s on barge-in.

---

## Flutter — TTS Streaming

### Simple Usage

```dart
final stream = TheStageFlutterSDK.infer_stream(
  model_name: 'tts',
  input_json: {'text': 'A long paragraph of text to speak aloud.'},
);

final player = TheStageAudioPlayer(sampleRate: 24000);
await player.start();

await for (final chunk in stream) {
  final audio = chunk['audio'] as Float32List?;
  if (audio != null && audio.isNotEmpty) {
    player.enqueue(audio);
  }
  if (chunk['is_final'] == true) break;
}

await player.drain();
await player.stop();
```

### Push-Based (LLM → TTS)

```dart
final ttsStream = TheStageFlutterSDK.infer_stream(
  model_name: 'tts',
  input_json: {'text': ''},
  stream_id: 'voice_agent_tts',
);

final player = TheStageAudioPlayer(sampleRate: 24000);
await player.start();

ttsStream.listen((chunk) {
  final audio = chunk['audio'] as Float32List?;
  if (audio != null) player.enqueue(audio);
});

final llmStream = TheStageFlutterSDK.infer_stream(
  model_name: 'llm',
  input_json: {
    'prompt': 'Tell me a joke',
    'max_new_tokens': 256,
  },
);

await for (final chunk in llmStream) {
  if (chunk['kind'] == 'text' && chunk['delta'] != null) {
    await TheStageFlutterSDK.send(
      stream_id: 'voice_agent_tts',
      text: chunk['delta'],
    );
  }
  if (chunk['is_final'] == true) {
    await TheStageFlutterSDK.finish_stream(stream_id: 'voice_agent_tts');
  }
}

await player.drain();
await player.stop();
```

---

## Stream Chunk Format

For the SDK-wide audio format contract (sample rates, mono Float, frame
sizes for VAD vs ASR vs TTS) see [Audio I/O Contract](./README.md#audio-io-contract).

### TTS Chunks

| Field | Type | Description |
|-------|------|-------------|
| `audio` | `[Float]` / `Float32List` | PCM audio samples, 24 kHz mono, normalized to `[-1.0, 1.0]` |
| `sample_rate` | `Int` | Always 24000 |
| `index` | `Int` | Sequential chunk number |
| `is_final` | `Bool` | `true` on the sentinel (empty) last chunk |
| `time_to_first_token` | `Double?` | Seconds to first audio chunk |
| `generated_tokens` | `Int?` | Decode step count (excludes prefill) |
| `tokens_per_second` | `Double?` | Decode speed: `steps / sum_of_step_durations` (measured inside decoder) |
| `total_seconds` | `Double?` | Wall-clock time from stream start to last chunk (final only) |

### LLM Chunks

| Field | Type | Description |
|-------|------|-------------|
| `delta` (Swift & Flutter) | `String?` | Decoded token text (nil on the final sentinel) |
| `index` | `Int` | Position in sequence |
| `is_final` | `Bool` | `true` for the sentinel chunk |
| `time_to_first_token` | `Double?` | Seconds to first token (final only) |
| `prompt_tokens` | `Int?` | Input token count (final only) |
| `generated_tokens` | `Int?` | Output token count (final only) |
| `tokens_per_second` | `Double?` | Generation speed (final only) |
| `total_seconds` | `Double?` | Wall-clock time (final only) |

---

## Flutter API Reference

### Lifecycle

```dart
await TheStageFlutterSDK.initialize(api_token: 'your_token');

await TheStageFlutterSDK.start_model(
  model_name: 'tts',
  engines_path: 'TheStageAI/neutts-multilingual',
  model_type: 'neutts-multilingual',
  revision: 'develop',
  config: {'voice_id': 'dave'},
);

await TheStageFlutterSDK.stop_model(model_name: 'tts');
```

### Streaming

```dart
final stream = TheStageFlutterSDK.infer_stream(
  model_name: 'tts',
  input_json: {'text': 'Hello world.'},
);

await TheStageFlutterSDK.send(stream_id: id, text: 'more text');
await TheStageFlutterSDK.finish_stream(stream_id: id);
await TheStageFlutterSDK.stop_stream(stream_id: id);
```

### Audio Player

```dart
final player = TheStageAudioPlayer(sampleRate: 24000);
await player.start();
player.enqueue(audioData);
await player.pause();
await player.resume();
await player.drain();
await player.stop();
```

---

## Cancellation

Cancel any active stream at any time:

```swift
// Swift — break from the for-await loop, or call streamer.cancel()
```

```dart
// Flutter
await TheStageFlutterSDK.stop_stream(stream_id: 'my_stream');
```

The stream will emit a final event with `kind: 'cancelled'` and close.

---

## Architecture

### TTSStreamer — Single Token Stream with Sentinels

```
Producer Task                          Consumer Task
─────────────                          ─────────────
sentence_stream                        token_stream
    │                                      │
    ▼                                      ▼
┌──────────┐                         ┌───────────┐
│preprocess│                         │is sentinel?│
└────┬─────┘                         └─┬───────┬─┘
     │                                 no      yes
     ▼                                 │        │
┌──────────────┐                       ▼        ▼
│decoder       │                  accumulate   flush
│  .prefill()  │                  codes        + fade-out
│  .decode_step│                       │        + reset
│  (loop)      │                       ▼
└────┬─────────┘                  ┌─────────┐
     │                            │codec.infer│
     ▼                            │(autorelease)│
yield tokens                      └────┬────┘
     │                                 │
     ▼                                 ▼
yield sentinel                    OLA + emit
```

The producer runs ahead — while the consumer decodes audio for the
current sentence, the producer is already preprocessing and generating
tokens for the next one. This eliminates inter-sentence pauses.

---

## Engine Requirements

Streaming and batch inference use the same model bundle — no extra
setup. Just use `infer_stream` instead of `infer`, or pull a push-based
`TTSStreamer` via `TheStageAI.shared.open_tts_streamer(...)`.

## Tuning the TTS Streamer

`TTSStreamConfig` exposes the codec-side chunking knobs that decide
time-to-first-audio and how seams between sentences sound. Defaults
match what the SDK ships with — only override these when you need to
trade latency against smoothness.

**Swift:**

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

// Or via the singleton:
let s2 = try ai.open_tts_streamer(
    model_name: "tts",
    config: TTSStreamConfig(first_frames_per_chunk: 12)
)
```

`infer_stream(text:stream_config:)` accepts the same struct when you
already have the full text up front.

**Flutter** — pass a nested `stream_config` map inside `input_json`:

```dart
final stream = TheStageFlutterSDK.infer_stream(
  model_name: 'tts',
  input_json: {
    'text': 'Hello, world.',
    'stream_config': {
      'first_frames_per_chunk': 12,
      'frames_per_chunk': 25,
      'lookforward': 5,
      'lookback': 50,
      'overlap_frames': 1,
    },
  },
);
```

See [NeuTTS — Streaming Hyperparameters](./tts.md#streaming-hyperparameters)
for the full field reference.
