# SileroVAD (Voice Activity Detection)

Stateful per-chunk speech detection. Drives the gate between mic
capture and Whisper / TTS, or runs as a batch segmenter to slice a
longer recording into speech regions.

VAD is reached through the singleton (JSON) path on both Swift and
Flutter — the response shape is identical.

## Basic Usage

**Swift:**

```swift
import TheStageSDK

let ai = TheStageAI.shared
try await ai.initialize(apiToken: "your-api-token")

try await ai.start_model(
    model_name: "vad",
    engines_path: "TheStageAI/silero-vad"
)

// Process audio in 512-sample chunks (32 ms @ 16 kHz).
let result = try ai.infer(
    model_name: "vad",
    input_json: ["audio": audio_chunk]
)
let probability = result[0]["probability"] as! Double
if probability > 0.5 {
    print("Speech detected!")
}
```

**Flutter:**

```dart
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';
import 'dart:typed_data';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

await TheStageFlutterSDK.start_model(
  model_name: 'vad',
  engines_path: 'TheStageAI/silero-vad',
);

// audio_chunk: Float32List, 16 kHz mono, exactly 512 samples.
final result = await TheStageFlutterSDK.infer(
  model_name: 'vad',
  input_json: {'audio': audio_chunk},
);
final probability = result[0]['probability'] as double;
if (probability > 0.5) {
  print('Speech detected!');
}
```

## Inputs / Outputs (single-chunk mode)

| Direction | Type | Description |
|---|---|---|
| input  `audio` | `[Float]` | 16 kHz mono PCM, **exactly 512 samples** (32 ms). |
| input  `reset_state` | `Bool` (default `false`) | Reset the LSTM state between independent utterances. |
| output `probability` | `Double` | Speech probability in `[0.0, 1.0]`. |

The single-chunk path returns just the probability — apply your own
threshold. For full segment extraction with hysteresis, see
[Segment Extraction](#segment-extraction-batch-mode).

## Audio I/O

- 16 kHz mono `[Float]`, samples in `[-1.0, 1.0]`.
- **Chunk size:** exactly 512 samples per `infer` call. Smaller chunks
  are zero-padded to 512 internally; larger chunks are rejected.
- **Stateful.** The model keeps an LSTM hidden state across calls.
  Pass `"reset_state": true` between independent utterances (or call
  `reset_state()` on the direct `SileroVAD` API).
- **Internal context.** A 64-sample carry-over from the previous chunk
  is prepended automatically — you don't need to overlap your capture
  yourself.

See [Audio I/O Contract](./README.md#audio-io-contract) for the
shared format used across VAD / ASR / TTS.

## Real-Time Usage Pattern

**Swift:**

```swift
let threshold = 0.5
for chunk in microphoneStream {                  // 512 samples each
    let result = try ai.infer(
        model_name: "vad",
        input_json: ["audio": chunk]
    )
    let probability = result[0]["probability"] as! Double

    if probability > threshold {
        speechBuffer.append(contentsOf: chunk)
    } else if !speechBuffer.isEmpty {
        // End of utterance — send to ASR.
        let transcript = try ai.infer(
            model_name: "stt",
            input_json: ["audio": speechBuffer]
        )
        speechBuffer.removeAll()
    }
}
```

**Flutter:**

```dart
const threshold = 0.5;
final speechBuffer = <double>[];

await for (final Float32List chunk in microphoneStream) {  // 512 samples each
  final result = await TheStageFlutterSDK.infer(
    model_name: 'vad',
    input_json: {'audio': chunk},
  );
  final probability = result[0]['probability'] as double;

  if (probability > threshold) {
    speechBuffer.addAll(chunk);
  } else if (speechBuffer.isNotEmpty) {
    final pcm = Float32List.fromList(speechBuffer);
    await TheStageFlutterSDK.infer(
      model_name: 'stt',
      input_json: {'audio': pcm},
    );
    speechBuffer.clear();
  }
}
```

For a production speech gate (onset/offset frames, pre-roll, max
accumulation, speculative ASR) use `TheStageVoiceAgent` — its VAD node
already implements all of this. See [voice_agent.md](./voice_agent.md).

## Segment Extraction (batch mode)

For batch processing, hand a longer buffer to VAD and let it return
the start/end sample indices of each speech segment using its built-in
hysteresis:

```swift
let result = try ai.infer(
    model_name: "vad",
    input_json: [
        "audio": long_audio,               // [Float] @ 16 kHz
        "extract_segments": true,           // enable segment mode
        "threshold": 0.5,                   // onset threshold
        "neg_threshold": -1.0,              // -1 → threshold - 0.15
        "min_speech_duration_ms": 250,
        "min_silence_duration_ms": 100,
        "speech_pad_ms": 30
    ]
)
// result is [[String: Any]] where each entry is:
//   [ "start": Int, "end": Int ]            // sample indices into long_audio
for seg in result {
    let start = seg["start"] as! Int
    let end = seg["end"] as! Int
    let slice = Array(long_audio[start..<end])
    // ... feed slice to ASR, persist, etc.
}
```

## Cleanup

**Swift:**

```swift
_ = try ai.stop_model(model_name: "vad")
```

**Flutter:**

```dart
await TheStageFlutterSDK.stop_model(model_name: 'vad');
```
