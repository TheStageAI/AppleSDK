# Speaker embedding

On-device speaker embedding for enrollment and cosine verification.
Public type: `SpeakerEmbedding` (family `thestage_speaker_embedding`).

Produces a **192-d L2-normalized** vector from **16 kHz mono** PCM. Default
compute device is **CPU** (ANE is not used for this model).

## Basic usage

**Swift:**

```swift
import TheStageSDK

try await TheStageAI.shared.initialize(apiToken: "your-api-token")

let sid = try await SpeakerEmbedding(
    engines_path: "TheStageAI/redimnet2"
)

// Enroll: embedding only
let enroll = try sid.infer(audio: pcm_16k_mono)   // or JSON path below
// Verify: pass reference embedding → cosine similarity
```

Via singleton JSON (same shape as Flutter):

```swift
try await TheStageAI.shared.start_model(
    model_name: "speaker_id",
    engines_path: "TheStageAI/redimnet2",
    model_type: "thestage_speaker_embedding"
)

// audio only → embedding
let out = try TheStageAI.shared.infer(
    model_name: "speaker_id",
    input_json: ["audio": pcm_16k_mono]
)
// audio + embedding → also "similarity"
```

**Flutter:**

```dart
await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

await TheStageFlutterSDK.start_model(
  model_name: 'speaker_id',
  engines_path: 'TheStageAI/redimnet2',
  // model_type when required by your plugin binding:
  // 'thestage_speaker_embedding'
);

final enrolled = await TheStageFlutterSDK.infer(
  model_name: 'speaker_id',
  input_json: {'audio': pcm16k},
);
final embedding = (enrolled[0]['embedding'] as List).cast<double>();

final check = await TheStageFlutterSDK.infer(
  model_name: 'speaker_id',
  input_json: {
    'audio': pcm16k,
    'embedding': embedding,
  },
);
final similarity = check[0]['similarity'] as double;
```

## Audio contract

| Item | Value |
|---|---|
| Sample rate | **16 000 Hz** mono Float / `Float32List` |
| Window | **2.0 s** (32 000 samples) — pad/trim trailing |
| Output dim | **192**, L2-normalized |
| Device default | `cpu` |

## Inputs / outputs (JSON)

| Key | Direction | Type | Notes |
|---|---|---|---|
| `audio` | in | `[Float]` / `Float32List` | Required |
| `embedding` | in | `[Double]` length 192 | Optional reference; if set, response includes similarity |
| `embedding` | out | `[Double]` | Probe embedding |
| `similarity` | out | `Double` | Cosine vs reference (only when reference provided) |

Caller chooses the accept threshold (voice agent default is **0.75**).

## Voice agent

Set `speaker_id` on `TheStageAgentConfig` (HF repo or local path) and call
`enroll_speaker(_:)`. Modes that need SID load
`model_name: "speaker_id"` with family `thestage_speaker_embedding`.
See [voice_agent.md](./voice_agent.md).

## Agent checklist

- Family id: `thestage_speaker_embedding`; common handle: `speaker_id`.
- Always 16 kHz mono; 2 s window.
- Verify = audio + reference embedding → `similarity`; you pick the threshold.
- Default device CPU — do not assume NPU.
