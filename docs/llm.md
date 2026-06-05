# LLM (Language Model)

On-device language model inference with batch and token-by-token
streaming. `TheStageLLM` wraps Qwen2 / Qwen3 / Gemma3 chat models with
KV cache, chat-template rendering, and stop-token policy.

Flutter consumers go through the singleton `start_model` +
`infer` / `infer_stream` (JSON) path — there is no direct LLM
constructor on Dart. Both surfaces share the same on-disk cache and
the same response shape.

## Basic Usage

**Swift** — direct constructor (recommended):

```swift
import TheStageSDK

let ai = TheStageAI.shared
try await ai.initialize(apiToken: "your-api-token")

let llm = try await TheStageLLM(
    engines_path: "TheStageAI/Qwen3-0.6B"   // HF repo id, or a local dir
)

let result = llm.infer(
    prompt: "What is 2+2?",
    system_prompt: "You are a helpful assistant.",
    max_new_tokens: 64
)
print(result.text)
```

**Flutter** — JSON path:

```dart
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

await TheStageFlutterSDK.start_model(
  model_name: 'llm',
  engines_path: 'TheStageAI/Qwen3-0.6B',
);

final result = await TheStageFlutterSDK.infer(
  model_name: 'llm',
  input_json: {
    'prompt': 'What is 2+2?',
    'system_prompt': 'You are a helpful assistant.',
    'max_new_tokens': 64,
  },
);
print(result[0]['text']);
```

## Inputs / Outputs

| Direction | Type | Description |
|---|---|---|
| input  `prompt` | `String` | The user message. |
| input  `system_prompt` | `String?` | Optional system message; defaults to the bundle's `default_system_prompt`. |
| input  `max_new_tokens` | `Int` (default 512) | Maximum tokens to generate. |
| input  `temperature` | `Float` (default 0.7) | Sampling temperature. |
| input  `top_k` | `Int` (default 20) | Top-k sampling. |
| input  `seed` | `UInt64?` | Deterministic sampling seed. |
| output `LLMResult.text` | `String` | Decoded response. |
| output `LLMResult.prompt_tokens` / `generated_tokens` | `Int` | Token counts. |
| output `LLMResult.tokens_per_second` | `Double` | Decode speed. |
| output `LLMResult.time_to_first_token` / `total_seconds` | `Double` | Latency breakdown. |
| output `LLMResult.stop_reason` | `String` | `"eos"` / `"max_new_tokens"` / `"stop_sequence"` / `"unknown"`. |

## Streaming

Token-by-token generation. Each chunk before the terminal sentinel
carries one delta of text; the final chunk has `is_final == true` and
the full per-call metrics.

**Swift:**

```swift
for await chunk in llm.infer_stream(
    prompt: "Tell me a story.",
    max_new_tokens: 512
) {
    if chunk.is_final {
        let tps = chunk.tokens_per_second ?? 0
        print("\n--- \(tps) tok/s ---")
    } else {
        print(chunk.text, terminator: "")
    }
}
```

**Flutter:**

```dart
final stream = TheStageFlutterSDK.infer_stream(
  model_name: 'llm',
  input_json: {
    'prompt': 'Tell me a story.',
    'max_new_tokens': 512,
  },
);

await for (final chunk in stream) {
  if (chunk['is_final'] == true) {
    final tps = chunk['tokens_per_second'] as double? ?? 0;
    print('\n--- $tps tok/s ---');
  } else {
    final delta = chunk['delta'] as String?;
    if (delta != null) stdout.write(delta);
  }
}
```

## Supported Models

| Model | HF repo | Parameters | Chat template |
|-------|---------|-----------:|---------------|
| Qwen2.5-1.5B | `TheStageAI/Qwen2.5-1.5B` | 1.5B | Qwen2 |
| Qwen3-0.6B | `TheStageAI/Qwen3-0.6B` | 0.6B | Qwen3 |
| Gemma3-1B | `TheStageAI/Gemma3-1B` | 1B | Gemma3 |

The bundle's `engines_path` accepts either a HuggingFace repo id or a
local directory. The chat template, EOS / stop tokens and KV-cache
horizon all come from the bundle — you don't pick them.

## Singleton API (`TheStageAI.shared`)

Use this when you want lifecycle (`stop_model`), JSON dispatch
(`infer(model_name:input_json:)`), or are driving the SDK from
Flutter. Both flows share the same on-disk cache.

```swift
try await ai.start_model(
    model_name: "llm",
    engines_path: "TheStageAI/Qwen3-0.6B"
)

let json = try ai.infer(
    model_name: "llm",
    input_json: [
        "prompt": "What is 2+2?",
        "system_prompt": "You are a helpful assistant.", // optional
        "max_new_tokens": 256,                            // optional
        "temperature": 0.7,                               // optional
        "top_k": 20,                                      // optional
        "seed": 42                                        // optional
    ]
)
let text = json[0]["text"] as! String
```

JSON streaming yields typed `InferenceStreamChunk` values — `delta`
carries each token's text:

```swift
let stream = try ai.infer_stream(
    model_name: "llm",
    input_json: ["prompt": "Tell me a story.", "max_new_tokens": 512]
)

for await chunk in stream {
    if !chunk.is_final, let delta = chunk.delta {
        print(delta, terminator: "")
    }
    if chunk.is_final, let tps = chunk.tokens_per_second {
        print("\n--- \(tps) tok/s ---")
    }
}
```

JSON response keys (matches the table above): `text`, `prompt_tokens`,
`generated_tokens`, `prefill_seconds`, `decode_seconds`,
`tokens_per_second`, `time_to_first_token`, `total_seconds`,
`stop_reason`.

The JSON path is single-turn. For multi-turn chat history use the
direct `TheStageLLM` API; chat templates are rendered for you.

The Flutter `TheStageFlutterSDK.infer` / `infer_stream` calls hit this
exact JSON path, so the response keys above apply unchanged on Dart.

## Full Constructor

```swift
let llm = try await TheStageLLM(
    engines_path: "TheStageAI/Qwen3-0.6B", // HF repo or local dir
    device: "gpu",                         // "gpu" | "cpu" | …
    max_context_size: 2048,
    chat_template: nil,                    // nil = use the bundle's
    revision: "main",                      // HF revision; ignored locally
    on_load_progress: nil                  // see "Load Progress" below
)
```

`TheStageAI.shared.initialize(apiToken:)` must have succeeded before
this call returns.

## Load Progress

`on_load_progress` is **optional**. When set, the handler fires through
four phases with a monotonic `fraction` in `0...1`:

```swift
let llm = try await TheStageLLM(
    engines_path: "TheStageAI/Qwen3-0.6B",
    on_load_progress: { p in
        // p.phase ∈ {.downloading, .extracting, .loading, .ready}
        // p.fraction in 0...1, monotonic across phases
        print("[\(p.model)] \(p.phase) \(Int(p.fraction * 100))%")
    }
)
```

Cache hits skip `.downloading` / `.extracting` and emit only
`.loading` followed by `.ready`. Failed loads do not emit `.ready`.
The same `on_load_progress` parameter is accepted by
`TheStageAI.shared.start_model(...)` and
`TheStageAI.shared.prefetch_engines(...)`.

For the full event contract see
[Load Progress in the index](./README.md#load-progress).

**Flutter:** progress events for every active `start_model` call are
multiplexed through a single global stream:

```dart
TheStageFlutterSDK.on_progress.listen((event) {
  if (event['model_name'] != 'llm') return;
  final phase    = event['phase']    as String?;   // downloading | extracting | loading | ready
  final fraction = event['progress'] as double?;   // 0.0 ... 1.0, monotonic
  print('[llm] $phase ${(fraction ?? 0) * 100}%');
});

await TheStageFlutterSDK.start_model(
  model_name: 'llm',
  engines_path: 'TheStageAI/Qwen3-0.6B',
);
```

## Prefetch Engines

If you'd rather download bundles ahead of time (e.g. on a "Download
models" screen) so a later construction is a pure local load, use
`prefetch_engines`:

```swift
let engines_dir = try await ai.prefetch_engines(
    repo_id: "TheStageAI/Qwen3-0.6B"
)

// Later — instant load, no network:
let llm = try await TheStageLLM(engines_path: engines_dir)
```

You don't need to call `prefetch_engines` before constructing
`TheStageLLM` / calling `start_model` — both pull the bundle on demand
and cache it.

## Cleanup

`TheStageLLM` is a normal Swift object — drop the reference to release
it. When you used the singleton API:

```swift
_ = try ai.stop_model(model_name: "llm")
```

**Flutter:**

```dart
await TheStageFlutterSDK.stop_model(model_name: 'llm');
```
