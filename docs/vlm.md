# VLM (Vision-Language Model)

On-device image → text with `TheStageVLM`. The shipping pack is Liquid
**LFM2.5-VL-450M**: a vision encoder + seq2seq decoder composite (same
leaf layout as Whisper — one root `qlip_bundle.json`, `encoder/` +
`decoder/`).

Flutter goes through `start_model` + `infer` (JSON). Swift can use the
direct constructor. Default HF revision comes from `ModelRevisionMap`
(omit `revision:`); for SDK **1.2.x** that pin is **`v1.2`**.

## Supported model

| Model | HF repo | Notes |
|---|---|---|
| LFM2.5-VL-450M | `TheStageAI/LFM2.5-VL-450M` | Fleet tag `v1.2` on SDK 1.2.x |

## Basic usage

**Swift:**

```swift
import TheStageSDK

let ai = TheStageAI.shared
try await ai.initialize(apiToken: "your-api-token")

let vlm = try await TheStageVLM(
    engines_path: "TheStageAI/LFM2.5-VL-450M",
    device: "npu"
)

guard let cgImage = /* CGImage from camera / gallery */ nil else { return }

var config = vlm.generation_defaults
config.max_new_tokens = 64
config.temperature = 0

let result = try vlm.infer(
    images: [cgImage],
    prompt: "Describe this image briefly.",
    config: config
)
print(result.text)
print(result.encode_seconds, result.prefill_seconds, result.decode_seconds)

// Streaming — same ``LLMStreamChunk`` shape as ``TheStageLLM.infer_stream``.
// Vision encode + fuse run before the first delta is yielded.
for await chunk in try vlm.infer_stream(
    images: [cgImage],
    prompt: "Describe this image briefly.",
    config: config
) {
    if chunk.is_final {
        print("tok/s", chunk.tokens_per_second ?? 0,
              "TTFT", chunk.time_to_first_token)
    } else {
        print(chunk.text, terminator: "")
    }
}
```

**Flutter** — JSON path (`image` file path or `image_base64`):

```dart
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

await TheStageFlutterSDK.start_model(
  model_name: 'vlm',
  engines_path: 'TheStageAI/LFM2.5-VL-450M',
);

final result = await TheStageFlutterSDK.infer(
  model_name: 'vlm',
  input_json: {
    'prompt': 'Describe this image briefly.',
    'image_base64': base64Jpeg, // or 'image': '/path/to.jpg'
    'max_new_tokens': 64,
    'temperature': 0,
  },
);
print(result[0]['text']);
```

Swift streaming is first-class (`infer_stream`). The Flutter JSON bridge
currently exposes blocking `infer` for VLM; use Swift (or a custom node)
when you need token deltas.

## Inputs / outputs

| Direction | Type | Description |
|---|---|---|
| input `images` / `image` / `image_base64` | `CGImage` / path / base64 | One or more images (Swift: `[CGImage]`) |
| input `prompt` | `String` | User text |
| input `system_prompt` | `String?` | Optional system message |
| input sampling fields | via `LLMGenerationConfig` / JSON | Same knobs as LLM (`max_new_tokens`, `temperature`, …) |
| output `text` | `String` | Caption / answer |
| output `encode_seconds` | `Double` | Vision encode |
| output `prefill_seconds` / `decode_seconds` | `Double` | Decoder phases |
| output `tokens_per_second` | `Double` | Decode tok/s |
| output `generated_tokens` | `Int` | Token count |
| output `stop_reason` | `String` | `"eos"` / `"max_new_tokens"` / … |

## Voice agent

VLM is **not** a built-in graph node. Host apps add a custom node (see
[voice_agent.md](./voice_agent.md) — `VLMCaptionNode` in the custom-nodes
demo) and keep the pack `ephemeral` in an app-level model roster.

## EngineBench

The `examples/engine_bench` app has a **VLM** tab: camera / photo library,
**Generate** (streaming text, same UX as the LLM tab), and **Benchmark**
(quiet non-streaming runs for encode / prefill / decode / tok/s). Use a
physical iPhone, **Release** configuration.

## Checklist

- `initialize` before `TheStageVLM` / `start_model`.
- Leave `revision:` nil unless you intentionally override the map.
- Prefer `device: "npu"` on Apple Silicon / ANE devices.
- Camera / photo library usage strings required for EngineBench-style apps.
