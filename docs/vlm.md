# VLM (Vision-Language Model)

`TheStageVLM` runs Liquid's LFM2.5-VL-450M on device: vision encoder +
seq2seq decoder shipped as one composite pack, same leaf layout as
Whisper (one root `qlip_bundle.json`, `encoder/` + `decoder/`).

Use it for captions, visual Q&A, OCR / document text, and structured
field extraction. Flutter goes through `start_model` + `infer` /
`infer_stream` (JSON). Swift can use the direct constructor with
first-class `infer_stream`.

Upstream, Liquid’s [LFM2.5-VL-450M blog](https://www.liquid.ai/blog/lfm2-5-vl-450m)
positions this 450M model for structured visual intelligence and reports
**OCRBench 684** — always validate on your own assets.

> **Main features**
>
> - **One pack, four jobs**: captions, visual Q&A, OCR, and structured
>   field extraction from a single `TheStageVLM` handle.
> - **Multi-image reasoning**: pass 2+ `CGImage`s (or `image_0` /
>   `image_1` / … in Flutter JSON) for compare / spot-the-diff /
>   aggregate-receipt tasks.
> - **Streaming (Swift + Flutter)**: Swift
>   `vlm.infer_stream(images:prompt:config:)` yields `LLMStreamChunk`;
>   Flutter `infer_stream(model_name:"vlm", input_json:)` yields the
>   same token deltas as JSON (`delta` / `is_final`). TTFT includes
>   vision encode. This is **not** TTS `open_streamer` — VLM is a
>   one-shot prompt stream like LLM.
> - **Deterministic OCR**: `temperature = 0` + a “transcribe exactly”
>   prompt gives repeatable text output.
> - **Same knobs as LLM**: `LLMGenerationConfig` fields (`max_new_tokens`,
>   `top_k`, `top_p`, `seed`, …) carry over; nothing new to learn.
> - **Voice-agent friendly**: use as a custom node
>   (`VLMCaptionNode`-style pattern) and keep the pack ephemeral so
>   ASR / LLM / TTS aren't crowded out.

## In this page

Here we will cover the following topics:

- [**Supported model**](#supported-models): LFM2.5-VL-450M feature matrix and context window.
- [**API surface**](#api-surface): Swift constructor, Flutter singleton, streaming shapes.
- [**Quick start**](#quick-start): caption a `CGImage` (Swift) and OCR a file path (Flutter).
- [**Configuration**](#configuration): the shared `LLMGenerationConfig` knobs.
- [**Inputs and outputs**](#inputs-and-outputs): how to pass images (Swift / Flutter / base64) and the result shape.
- [**Lifecycle**](#lifecycle): initialize → construct → infer → cleanup.
- [**Usage Guides**](#usage-guides): load from disk / memory, formats, caption, VQA, multi-image compare, OCR (worked example), structured JSON, Flutter I/O, streaming, latency breakdown, voice-agent wiring.
- [**Troubleshooting**](#troubleshooting): empty captions, OCR misses, mixed languages, wrong encoding / orientation, slow first token, Flutter path errors, load failures.

## Supported models

| Model | HF repo | Size | Device | Fleet pin |
|-------|---------|-----:|--------|-----------|
| LFM2.5-VL-450M | `TheStageAI/LFM2.5-VL-450M` | 450M | NPU | v1.2 |

| Feature | LFM2.5-VL-450M |
|---------|:--------------:|
| Caption / VQA | yes |
| OCR / document text | yes |
| Structured field extraction | yes |
| Streaming (Swift) | yes |
| Flutter `infer` | yes |
| Flutter `infer_stream` | yes |

Image tokens and text share one fixed context window — crop dense pages
or shorten prompts if answers truncate.

## API surface

| Purpose | Swift | Flutter |
|---------|-------|---------|
| Init | `try await TheStageVLM(engines_path:device:)` | `start_model(model_name:"vlm", engines_path:)` |
| One-shot | `vlm.infer(images:prompt:config:)` → `LLMInferenceResult` | `infer(model_name:"vlm", input_json:)` |
| Streaming | `vlm.infer_stream(images:prompt:config:)` → `LLMStreamChunk` | `infer_stream(model_name:"vlm", input_json:)` → `{delta, is_final, …}` |
| Config | `LLMGenerationConfig` (same as LLM) | same keys inside `input_json` |
| Progress | `on_load_progress` | `TheStageFlutterSDK.on_progress` |
| Cleanup | drop the object | `stop_model(model_name:"vlm")` |

## Quick start

**Swift — caption a CGImage with streaming:**

```swift
import TheStageSDK

try await TheStageAI.shared.initialize(apiToken: "your-api-token")

let vlm = try await TheStageVLM(
    engines_path: "TheStageAI/LFM2.5-VL-450M",
    device: "npu"
)

var config = vlm.generation_defaults
config.max_new_tokens = 96
config.temperature = 0        // deterministic for OCR / captions

for await chunk in vlm.infer_stream(
    images: [cg_image],
    prompt: "Describe this image in one sentence.",
    config: config
) {
    if !chunk.is_final { print(chunk.text, terminator: "") }
}
```

**Flutter — OCR a file path (JSON):**

```dart
await TheStageFlutterSDK.initialize(api_token: 'your-api-token');
await TheStageFlutterSDK.start_model(
  model_name: 'vlm',
  engines_path: 'TheStageAI/LFM2.5-VL-450M',
);

final out = await TheStageFlutterSDK.infer(
  model_name: 'vlm',
  input_json: {
    'image': '/absolute/path/to/document.png',
    'prompt': 'Extract the visible text verbatim.',
    'max_new_tokens': 512,
    'temperature': 0.0,
  },
);
print(out[0]['text']);
```

## Configuration

Same `LLMGenerationConfig` knobs as [LLM](./llm.md#configuration). Start
from `vlm.generation_defaults`.

| Knob | Notes |
|------|-------|
| `max_new_tokens` | Raise for dense OCR / long JSON; check `stop_reason` |
| `temperature` | Use `0` for OCR / structured extraction |
| `top_k` / `top_p` / `min_p` / `seed` | Same meaning as LLM |

## Inputs and outputs

**Inputs**

| Field | Where | Meaning |
|-------|-------|---------|
| `images` | Swift | One or more `CGImage` |
| `image` / `image_N` | Flutter JSON | File path (JPEG / PNG / BMP) |
| `image_base64` / `image_base64_N` | Flutter JSON | Base64 image bytes |
| `image_bytes` | JSON | Raw image bytes |
| `prompt` | both | Required; wording drives caption / VQA / OCR |
| `system_prompt` | both | Optional |

At least one image is required for a useful call.

**Result (`LLMInferenceResult` / JSON):**

| Field | Meaning |
|-------|---------|
| `text` | Caption / answer / OCR text |
| `encode_seconds` | Vision encode |
| `prefill_seconds` / `decode_seconds` | Decoder phases |
| `tokens_per_second` | Decode tok/s |
| `prompt_tokens` / `generated_tokens` | Token counts |
| `total_seconds` | Wall time |
| `stop_reason` | `eos` / `max_new_tokens` / … |

Vision encode runs before the first delta — TTFT includes encode.

## Lifecycle

1. `initialize(apiToken:)` once per process.
2. Construct `TheStageVLM` or `start_model` — first call downloads and
   compiles the pack.
3. Call `infer` / `infer_stream`.
4. Drop the object (Swift) or `stop_model` (Flutter) when done.

## Usage Guides

Jump to a recipe:

- [How do I load an image from disk?](#how-do-i-load-an-image-from-disk)
- [How do I pass an image from memory?](#how-do-i-pass-an-image-from-memory)
- [Which formats work? Do I resize / normalize?](#which-formats-work-do-i-resize-normalize)
- [How do I caption / describe an image?](#how-do-i-caption-describe-an-image)
- [How do I ask a question about an image?](#how-do-i-ask-a-question-about-an-image)
- [How do I compare / reason across multiple images?](#how-do-i-compare-reason-across-multiple-images)
- [How do I OCR / extract text? (worked example)](#how-do-i-ocr-extract-text-worked-example)
- [How do I pull structured fields from a document?](#how-do-i-pull-structured-fields-from-a-document)
- [How do I pass images from Flutter?](#how-do-i-pass-images-from-flutter)
- [How do I stream captions?](#how-do-i-stream-captions)
- [How do I read the latency breakdown?](#how-do-i-read-the-latency-breakdown)
- [How do I wire VLM into a voice agent?](#how-do-i-wire-vlm-into-a-voice-agent)

### How do I load an image from disk?

```swift
import TheStageSDK

let image: CGImage = try ImageIOHelpers.load_cgimage(
    path: "/path/to/photo.jpg"   // JPEG / PNG / HEIC / …
)
// pass to TheStageVLM.infer(images: [image], …)
```

Flutter / JSON: `"image": "/path/to/photo.jpg"` (`String` path).

### How do I pass an image from memory?

```swift
// Data (network download, photo picker bytes, …)
let jpeg_data: Data = /* … */
let image: CGImage = try ImageIOHelpers.load_cgimage(data: jpeg_data)

// Already a CGImage (camera / UIImage.cg_image) — pass directly
let images: [CGImage] = [image]
let result = try vlm.infer(
    images: images,
    prompt: "Describe this image briefly.",
    config: config
)
print(result.text)  // String
```

Flutter / JSON: `"image_base64": "<base64>"` or `image_bytes`.

### Which formats work? Do I resize / normalize?

| | |
|---|---|
| Formats | JPEG, PNG, HEIC, and anything ImageIO decodes |
| Resize | **No** — the vision encoder resizes |
| Normalize | **No** — do not apply ImageNet mean/std yourself |

### How do I caption / describe an image?

Prefer `temperature = 0` for stable captions.

**Swift:**

```swift
import TheStageSDK

let vlm = try await TheStageVLM(
    engines_path: "TheStageAI/LFM2.5-VL-450M",
    device: "npu"
)

let cg_image: CGImage = try ImageIOHelpers.load_cgimage(path: "/path/to/photo.jpg")

var config = vlm.generation_defaults
config.max_new_tokens = 64
config.temperature = 0

let result = try vlm.infer(
    images: [cg_image],
    prompt: "Describe this image briefly.",
    config: config
)
print(result.text)  // String
```

**Flutter:**

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
    'image': imagePath, // or 'image_base64': base64Jpeg
    'max_new_tokens': 64,
    'temperature': 0,
  },
);
print(result[0]['text']);
```

### How do I ask a question about an image?

Put the question in `prompt` and pass the image. Short answers → small
`max_new_tokens`; detailed answers → raise the cap and check
`stop_reason`.

```swift
var config = vlm.generation_defaults
config.max_new_tokens = 128
config.temperature = 0

let result = try vlm.infer(
    images: [cg_image],
    prompt: "How many people are visible, and what are they doing?",
    config: config
)
print(result.text)
print(result.stop_reason)
```

### How do I compare / reason across multiple images?

`images:` takes a Swift array — pass 2+ `CGImage`s to ask the model
about them together (compare, spot-the-diff, combine receipts, etc.).
Image tokens for each frame share the same context window, so keep
the frame count small (2–4 for LFM2.5-VL-450M) and the prompt short.

**Swift — spot-the-difference between two photos:**

```swift
var config = vlm.generation_defaults
config.max_new_tokens = 192
config.temperature = 0

let before: CGImage = try ImageIOHelpers.load_cgimage(path: "/tmp/desk_before.jpg")
let after:  CGImage = try ImageIOHelpers.load_cgimage(path: "/tmp/desk_after.jpg")

let result = try vlm.infer(
    images: [before, after],
    prompt:
        "The first image is BEFORE, the second is AFTER. "
        + "List the visible differences as a short bullet list.",
    config: config
)
print(result.text)
```

**Flutter** uses numbered keys — `image_0`, `image_1`, … (or
`image_base64_0`, `image_base64_1`, …). Numbering starts at `0` and
must be contiguous.

```dart
final result = await TheStageFlutterSDK.infer(
  model_name: 'vlm',
  input_json: {
    'prompt':
      'The first image is BEFORE, the second is AFTER. '
      'List the visible differences as a short bullet list.',
    'image_0': '/tmp/desk_before.jpg',
    'image_1': '/tmp/desk_after.jpg',
    'max_new_tokens': 192,
    'temperature': 0,
  },
);
print(result[0]['text']);
```

If you get truncated answers, raise `max_new_tokens` or trim the
prompt — image tokens + text share one context window.

### How do I OCR / extract text? (worked example)

Sample image: [`assets/vlm_ocr_sample.png`](./assets/vlm_ocr_sample.png).
Use temperature `0` and an explicit “transcribe exactly” prompt.

**Swift:**

```swift
import TheStageSDK

let vlm = try await TheStageVLM(
    engines_path: "TheStageAI/LFM2.5-VL-450M",
    device: "npu"
)
let cg_image: CGImage = try ImageIOHelpers.load_cgimage(
    path: "docs/assets/vlm_ocr_sample.png"  // or your receipt path
)

var config = vlm.generation_defaults
config.max_new_tokens = 256
config.temperature = 0

let result = try vlm.infer(
    images: [cg_image],
    prompt: "Transcribe all visible text in this image exactly.",
    config: config
)
print(result.text)
// Timing fields match the table below on a local Mac NPU run.
print(result.encode_seconds, result.prefill_seconds,
      result.decode_seconds, result.tokens_per_second,
      result.stop_reason)
```

**Flutter:**

```dart
final result = await TheStageFlutterSDK.infer(
  model_name: 'vlm',
  input_json: {
    'prompt': 'Transcribe all visible text in this image exactly.',
    'image': ocrSamplePath, // or 'image_base64': base64Png
    'max_new_tokens': 256,
    'temperature': 0,
  },
);
print(result[0]['text']);
```

**Expected output** (same sample, Mac NPU):

```text
THESTAGE AI
Order #48291
Total: $42.50
Paid: 11 Aug 2026
```

| Metric | Value |
|--------|------:|
| Encode | 0.342 s |
| Prefill | 0.063 s |
| Decode | 0.162 s |
| Tokens / s | 160.8 |
| Stop reason | eos |

Tips for denser pages: crop the text region, improve contrast, keep
temperature at 0, and raise `max_new_tokens` if `stop_reason` is
`max_new_tokens`.

### How do I pull structured fields from a document?

Ask for JSON (or a fixed schema) in the prompt, then parse on the app
side — same pattern as motivating tool I/O on the LLM side.

```swift
var config = vlm.generation_defaults
config.max_new_tokens = 256
config.temperature = 0

let prompt =
    "Extract fields as JSON only, no markdown: "
    + #"{"merchant":string,"order_id":string,"total":string,"paid_date":string}"#
let result = try vlm.infer(
    images: [cg_image],  // same load as OCR example
    prompt: prompt,
    config: config
)
// Parse result.text with JSONSerialization / Codable in the app
print(result.text)
```

If the model wraps JSON in fences or adds prose, strip then decode.
Retry with a stricter system prompt if needed.

### How do I pass images from Flutter?

Use either a filesystem **`image`** path or **`image_base64`**
(JPEG/PNG/BMP). Multiple images: `image_0`, `image_1`, … or
`image_base64_0`, …

```dart
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

Ensure the path is readable by the iOS app container, or pass base64.
Wrong encoding / empty string yields empty captions.

### How do I stream captions?

Streaming uses the same token-delta path as LLM — **not** TTS
`open_streamer`. Pass the full prompt (and image) up front; chunks
arrive as text deltas. Vision encode + fuse run **before** the first
delta — TTFT includes encode.

**Swift** — `LLMStreamChunk` (`.text` / `.is_final`):

```swift
var config = vlm.generation_defaults
config.max_new_tokens = 64
config.temperature = 0

for await chunk in try vlm.infer_stream(
    images: [cg_image],
    prompt: "Describe this image briefly.",
    config: config
) {
    if chunk.is_final {
        print(
            "tok/s", chunk.tokens_per_second ?? 0,
            "TTFT", chunk.time_to_first_token
        )
    } else {
        print(chunk.text, terminator: "")
    }
}
```

**Flutter** — same `input_json` keys as blocking `infer`; consume
`delta` until `is_final`:

```dart
await TheStageFlutterSDK.start_model(
  model_name: 'vlm',
  engines_path: 'TheStageAI/LFM2.5-VL-450M',
);

final buffer = StringBuffer();
await for (final chunk in TheStageFlutterSDK.infer_stream(
  model_name: 'vlm',
  input_json: {
    'image': '/absolute/path/to/photo.jpg',
    'prompt': 'Describe this image briefly.',
    'max_new_tokens': 64,
    'temperature': 0.0,
  },
)) {
  final delta = chunk['delta'] as String?;
  if (delta != null && delta.isNotEmpty) {
    buffer.write(delta);
    // update UI with buffer.toString()
  }
  if (chunk['is_final'] == true) {
    print('tok/s ${chunk['tokens_per_second']}');
    break;
  }
}
print(buffer.toString());
```

Multi-image works the same way — pass `image_0` / `image_1` (or
`image_base64_0` / …) in `input_json`.

### How do I read the latency breakdown?

| Field | Meaning |
|---|---|
| `encode_seconds` | Vision encoder wall time (dominant on first token) |
| `prefill_seconds` | Decoder prefill after fused multimodal prompt |
| `decode_seconds` | Autoregressive token generation |
| `tokens_per_second` | Decode throughput |
| `total_seconds` | End-to-end wall time |

Show a spinner through encode; stream or reveal text once decode
starts. The OCR worked example above is a concrete Mac breakdown
(`encode=0.342s`, `prefill=0.063s`, `decode=0.162s`, `tok/s=160.8`).

### How do I wire VLM into a voice agent?

VLM is **not** a built-in graph node. Host apps add a custom node and
keep the pack `ephemeral` in an app-level model roster so vision does
not fight ASR/LLM/TTS for ANE/RAM.

See [voice_agent.md](./voice_agent.md) — custom nodes + ports, and the
`VLMCaptionNode` pattern in `examples/voice_agent_custom_nodes`
(prefer `lifecycle: external` / `ModelRoster.withEphemeral`, gate on
quiet agent states).

## Troubleshooting

### Bad or empty captions

1. Confirm at least one image loaded (path exists / base64 decodes /
   `CGImage` non-nil).
2. Use a clear prompt (`Describe this image briefly.`).
3. Check `stop_reason` and raise `max_new_tokens` if truncated.
4. Prefer `device: "npu"` and a Release build on device.

### OCR misses small or blurry text

1. Crop / zoom the text region; improve contrast.
2. Keep `temperature = 0`; raise `max_new_tokens` for dense pages.
3. Re-check orientation (upright text works best).
4. Validate on your asset — blog OCRBench **684** is an upstream signal,
   not a guarantee for every photo.

### Mixed languages in one frame

1. Ask explicitly in the prompt (e.g. “Transcribe all languages
   exactly”).
2. Crop language regions and run separate calls if quality drops.

### Wrong image encoding or orientation

1. Flutter: use JPEG/PNG base64 or a real file path — not a Flutter
   asset key the native side cannot open.
2. Rotate EXIF-upright before encode when the camera writes sideways
   buffers.
3. Empty `image` / `image_base64` silently skips that source — log
   whether any `CGImage` was produced.

### Slow first token

1. `encode_seconds` is expected before the first delta — show progress.
2. Prefetch the pack; warm with a tiny throwaway image at startup.
3. Avoid loading VLM while ASR/LLM/TTS are all resident (offload /
   ephemeral roster).

### Flutter path / base64 errors

1. Prefer absolute container paths or `image_base64`.
2. Read `result[0]['text']` (list of maps), not a bare string.
3. For live tokens use `infer_stream(model_name: 'vlm', …)` and read
   `chunk['delta']` until `is_final`; blocking `infer` still returns
   `result[0]['text']`.

### NPU load failures

1. `initialize` before `TheStageVLM` / `start_model`.
2. Attach `on_load_progress` / Flutter `on_progress`.
3. Free RAM (stop other models); retry `device: "npu"`, then `"gpu"` if
   needed for diagnosis.

### Truncated answers

1. If `stop_reason == "max_new_tokens"`, raise the cap and retry.
2. Long OCR + JSON prompts share the pack’s context window with vision
   tokens — shorten the prompt or crop the image.

## Load Progress

`on_load_progress` is **optional**. When set, the handler fires through
four phases with a monotonic `fraction` in `0...1`:

```swift
let vlm = try await TheStageVLM(
    engines_path: "TheStageAI/LFM2.5-VL-450M",
    on_load_progress: { p in
        print("[\(p.model)] \(p.phase) \(Int(p.fraction * 100))%")
    }
)
```

Cache hits skip `.downloading` / `.extracting` and emit only
`.loading` followed by `.ready`. Failed loads do not emit `.ready`.
The same handler is accepted by `start_model` and `prefetch_engines`.

For the full event contract see
[Load Progress in the index](./README.md#load-progress).

**Flutter:**

```dart
TheStageFlutterSDK.on_progress.listen((event) {
  if (event['model_name'] != 'vlm') return;
  final phase    = event['phase']    as String?;
  final fraction = event['progress'] as double?;
  print('[vlm] $phase ${(fraction ?? 0) * 100}%');
});

await TheStageFlutterSDK.start_model(
  model_name: 'vlm',
  engines_path: 'TheStageAI/LFM2.5-VL-450M',
);
```

## Prefetch Engines

```swift
let engines_dir = try await ai.prefetch_engines(
    repo_id: "TheStageAI/LFM2.5-VL-450M"
)

// Later — instant load, no network:
let vlm = try await TheStageVLM(engines_path: engines_dir, device: "npu")
```

You don't need to prefetch before construct / `start_model` — both pull
on demand and cache.

## Cleanup

`TheStageVLM` is a normal Swift object — drop the reference to release
it. When you used the singleton API:

```swift
_ = try ai.stop_model(model_name: "vlm")
```

**Flutter:**

```dart
await TheStageFlutterSDK.stop_model(model_name: 'vlm');
```
