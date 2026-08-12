# SileroVAD (Voice Activity Detection)

Stateful per-chunk speech detection. Drives the gate between mic
capture and Whisper / TTS, or runs as a batch segmenter to slice a
longer recording into speech regions.

VAD is reached through the singleton (JSON) path on both Swift and
Flutter — the response shape is identical.

## Supported Models

| Model | HF repo | Notes |
|-------|---------|-------|
| Silero VAD | TheStageAI/silero-vad | Stateful LSTM, 512-sample chunks @ 16 kHz |

## API Reference

### Init

```swift
import TheStageSDK

let ai = TheStageAI.shared
try await ai.initialize(apiToken: "your-api-token")

try await ai.start_model(
    model_name: "vad",
    engines_path: "TheStageAI/silero-vad"
)
```

| Arg | Description |
|-----|-------------|
| engines_path | HF repo or local dir (silero-vad) |
| model_name | Handle, typically vad |

Audio: **16 kHz mono** Float in [-1, 1]. Exactly **512 samples** (32 ms)
per Infer call. See [Audio I/O Contract](./README.md#audio-io-contract).

### Infer

Single-chunk probability:

```swift
let result = try ai.infer(
    model_name: "vad",
    input_json: ["audio": audio_chunk]  // exactly 512 samples
)
let probability = result[0]["probability"] as! Double
```

| Input | Description |
|-------|-------------|
| audio | 16 kHz mono, exactly 512 samples |
| reset_state | true between independent utterances (default false) |

Batch segment extraction (longer buffer):

```swift
let result = try ai.infer(
    model_name: "vad",
    input_json: [
        "audio": long_audio,
        "extract_segments": true,
        "threshold": 0.5,
        "neg_threshold": -1.0,
        "min_speech_duration_ms": 250,
        "min_silence_duration_ms": 100,
        "speech_pad_ms": 30
    ]
)
// each entry: ["start": Int, "end": Int]  sample indices
```

### Stream

— (no dedicated streamer). Call Infer on successive 512-sample mic
chunks. For a production speech gate use
[Voice Agent](./voice_agent.md).

Realtime pattern: threshold on `probability`, accumulate voiced chunks,
hand buffer to ASR on silence. Smaller chunks are zero-padded to 512;
larger chunks are rejected. LSTM state carries across calls — pass
`reset_state: true` between independent utterances. A 64-sample
internal carry-over is prepended automatically.

### Config

| Knob | Description |
|------|-------------|
| threshold | Onset speech probability (segment mode) |
| neg_threshold | End threshold (−1 → threshold − 0.15) |
| min_speech_duration_ms | Min segment length |
| min_silence_duration_ms | Silence gap to split |
| speech_pad_ms | Padding around segments |
| reset_state | Clear LSTM between utterances |

Single-chunk mode has no threshold in the API — apply your own on
`probability`.

### Outputs

| Field | Description |
|-------|-------------|
| probability | Speech prob in [0, 1] (single-chunk) |
| start / end | Sample indices (segment mode rows) |

## Usage Guides

### How do I run VAD from Flutter?

```dart
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';
import 'dart:typed_data';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');
await TheStageFlutterSDK.start_model(
  model_name: 'vad',
  engines_path: 'TheStageAI/silero-vad',
);

// audio_chunk: Float32List, 16 kHz mono, exactly 512 samples
final result = await TheStageFlutterSDK.infer(
  model_name: 'vad',
  input_json: {'audio': audio_chunk},
);
final probability = result[0]['probability'] as double;
```

## Cleanup

**Swift:** `_ = try ai.stop_model(model_name: "vad")`  
**Flutter:** `await TheStageFlutterSDK.stop_model(model_name: 'vad');`

## Agent checklist

- Input **16 kHz** mono; exactly **512 samples** per `infer` (32 ms).
- Call `reset_state()` between independent utterances.
