# voice_agent_custom_nodes

Flutter demo for **custom voice-agent nodes** on TheStage Apple SDK
**`1.3.0`**.

Shows how to attach host-owned nodes (`extraNodes`), caption images with
an ephemeral VLM, tune sample rates / AEC, and park resident models
around a quiet-state burst.

| | |
| --- | --- |
| Example version | **`1.3.0`** (see [`VERSION`](./VERSION)) |
| SDK pin | Flutter plugin `ref: 1.3.0` |
| Platforms | Physical iPhone, **iOS 18+** |

## What it demonstrates

1. **`extraNodes`** — `EventLogNode` (`onEvent`) + app-local `VLMCaptionNode`
2. **VLM captions** — pick camera / gallery image → caption UI +
   `Documents/captions.txt` (quiet states only; parks LLM/STT/TTS)
3. **`sample_rate_out`** — 16 / 24 / 48 kHz (TTS resampled in `AudioEngineNode`)
4. **`aec_method`** — `vpio` | `neural` | `none`
5. **`ModelRoster`** — resident pipeline + `withEphemeral` / `withEphemeralSwap` for VLM

Node sources under `lib/nodes/` are **app-local recipes** (copy into your
host). They are not part of the plugin surface.

See also [`docs/voice_agent.md`](../../docs/voice_agent.md) (Events,
custom nodes, residency) and [`docs/vlm.md`](../../docs/vlm.md).

## Prerequisites

- API token from [app.thestage.ai](https://app.thestage.ai)
- Physical iPhone on iOS 18+ (camera / mic / photos permissions)
- Xcode signing: set your **Team** and a unique bundle id

## Setup

```bash
cd examples/voice_agent_custom_nodes
cp secrets.example.json secrets.json
# Edit secrets.json — set TS_API_TOKEN only (never commit this file)

flutter pub get
```

Open `ios/Runner.xcodeproj` → **Signing & Capabilities** → Team + Bundle ID.

## Run

```bash
flutter devices
flutter run --release \
  --dart-define-from-file=secrets.json \
  -d <YOUR_IPHONE_DEVICE_ID>
```

## Hugging Face models (defaults)

Revision comes from the SDK ``ModelRevisionMap`` for this line — do not
hardcode `vA.B` unless you intentionally override:

| Role | HF repo |
| --- | --- |
| VAD | `TheStageAI/silero-vad` |
| STT | `TheStageAI/thewhisper-large-v3-turbo` |
| TTS | `TheStageAI/Qwen3-TTS-12Hz-0.6B-Base` |
| LLM | `TheStageAI/LFM2.5-350M` (or picker) |
| VLM | `TheStageAI/LFM2.5-VL-450M` (SDK 1.2 → HF `v1.2`) |
| Neural AEC | `TheStageAI/dtln-aec` (when `aec_method: neural`) |

First load downloads and compiles on-device; later launches reuse the cache.

## Notes

- Prefer quiet agent states (`idle` / `listening` / `sleeping`) for VLM.
- Do not commit `secrets.json` or a filled API token.
- Unit tests: `flutter test` (no device / token required for roster/node tests).
