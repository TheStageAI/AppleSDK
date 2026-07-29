# LLM (Language Model)

On-device language model inference with batch and token-by-token
streaming. `TheStageLLM` wraps Qwen3 / Gemma3 / LFM2.5 chat models with
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

For full sampling control, pass an `LLMGenerationConfig`. Start from the
bundle's `generation_defaults` (a per-model sampling preset baked into the
bundle) and override only what you need:

```swift
var config = llm.generation_defaults   // proper preset for this model
config.max_new_tokens = 256
config.temperature = 0.7
config.top_p = 0.8
config.repetition_penalty = 1.1
config.enable_thinking = false         // Qwen3 / thinking-capable models

let result = llm.infer(
    prompt: "List 20 facts about London.",
    config: config
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
| input  `min_new_tokens` | `Int` (default 0) | Swift `LLMGenerationConfig` only — not applied via JSON overlay. |
| input  `temperature` | `Float` | Sampling temperature. `0` = greedy. |
| input  `top_k` | `Int` | Keep only the top-k logits. `0` = disabled. |
| input  `top_p` | `Float` | Nucleus sampling cumulative-probability cap. `1.0` = disabled. |
| input  `min_p` | `Float` | Drop tokens below `min_p × p(max)`. `0.0` = disabled. |
| input  `repetition_penalty` | `Float` | Penalize already-seen tokens. `1.0` = disabled. |
| input  `enable_thinking` | `Bool` | Toggle the model's thinking/reasoning prelude (Qwen3 etc.). |
| input  `seed` | `UInt64?` | Deterministic sampling seed. |
| output `LLMResult.text` | `String` | Decoded response. |
| output `LLMResult.prompt_tokens` / `generated_tokens` | `Int` | Token counts. |
| output `LLMResult.tokens_per_second` | `Double` | Decode speed. |
| output `LLMResult.time_to_first_token` / `total_seconds` | `Double` | Latency breakdown. |
| output `LLMResult.stop_reason` | `String` | `"eos"` / `"max_new_tokens"` / `"stop_sequence"` / `"unknown"`. |

Sampling defaults are **per-model**: each bundle ships a tuned preset
(`generation_defaults`). When you omit a sampling field it keeps the bundle's
preset value, so you don't have to know the right `temperature` / `top_p` for
each family. Pass `LLMGenerationConfig` (above) to override.

## Generation parameters (what to set)

Omit sampling fields unless you have a reason — the bundle preset is usually
right. Override only the knobs you care about.

| Knob | Plain meaning | Typical range | Notes |
|---|---|---|---|
| `max_new_tokens` | Hard cap on reply length | 64–1024 | Hit this → `stop_reason == "max_new_tokens"` (truncated). |
| `temperature` | How random next-token picks are | 0–1.2 | `0` = greedy / most deterministic. Higher = more variety (and more nonsense risk). |
| `top_k` | Keep only the *k* most likely tokens | 0 / 10–50 | `0` = off. Lower = safer, more repetitive. |
| `top_p` | Keep the smallest set whose probs sum to *p* | 0.8–1.0 | `1.0` = off. Often used with moderate temperature. |
| `min_p` | Drop tokens weaker than `min_p × p(best)` | 0–0.1 | `0` = off. Cuts long-tail noise. |
| `repetition_penalty` | Discourage already-seen tokens | 1.0–1.2 | `1.0` = off. Helpful if the model loops. |
| `enable_thinking` | Qwen3 reasoning prelude on/off | true/false | Off for short chat UX; on for harder reasoning. |
| `seed` | Fix the RNG | any `UInt64` | Same device + same bundle + same inputs → same text. |

**Swift:** start from `llm.generation_defaults`, mutate fields, pass `config:`.  
**Flutter / JSON:** put the same keys in `input_json` (except `min_new_tokens`, which is Swift-only).

### Real-world recipes

Copy a block that matches the product job. Values are starting points — tune on device.

**1. Short factual Q&A** (support bot, FAQ, “what is…?”)

```swift
var config = llm.generation_defaults
config.max_new_tokens = 128
config.temperature = 0.3
config.top_k = 20
config.top_p = 0.9
config.repetition_penalty = 1.05
config.enable_thinking = false
```

```dart
input_json: {
  'prompt': 'What is the capital of France?',
  'system_prompt': 'Answer in one short sentence. No fluff.',
  'max_new_tokens': 128,
  'temperature': 0.3,
  'top_k': 20,
  'top_p': 0.9,
  'repetition_penalty': 1.05,
  'enable_thinking': false,
}
```

**2. Creative / chatty reply** (story, brainstorm, casual chat)

```swift
var config = llm.generation_defaults
config.max_new_tokens = 512
config.temperature = 0.9
config.top_k = 40
config.top_p = 0.95
config.enable_thinking = false
```

**3. Longer structured answer** (summarize, explain, bullet list)

```swift
var config = llm.generation_defaults
config.max_new_tokens = 768
config.temperature = 0.5
config.top_p = 0.9
config.repetition_penalty = 1.1
config.enable_thinking = false
```

Check `result.stop_reason`. If it is `"max_new_tokens"`, raise the cap and retry.

**4. Hard reasoning (Qwen3 thinking)**

```swift
var config = llm.generation_defaults
config.max_new_tokens = 1024
config.temperature = 0.6
config.enable_thinking = true
```

Thinking tokens still count toward `max_new_tokens` — budget headroom.

**5. Deterministic tests / golden fixtures**

```swift
var config = llm.generation_defaults
config.temperature = 0
config.seed = 42
config.max_new_tokens = 64
```

Same seed is only guaranteed on the **same device + same bundle revision**.

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
| Qwen3-0.6B | `TheStageAI/Qwen3-0.6B` | 0.6B | Qwen3 |
| Gemma3-1B | `TheStageAI/Gemma3-1B` | 1B | Gemma3 |
| LFM2.5-230M | `TheStageAI/LFM2.5-230M` | 230M | LFM2 |
| LFM2.5-350M | `TheStageAI/LFM2.5-350M` | 350M | LFM2 |

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
        "top_p": 0.8,                                     // optional
        "min_p": 0.0,                                     // optional
        "repetition_penalty": 1.1,                        // optional
        "enable_thinking": false,                         // optional
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
    device: "gpu",                         // "gpu" | "cpu" | "npu"
    chat_template: nil,                    // nil = use the bundle's
    default_system_prompt: nil,            // nil = use the bundle's
    eos_token_id: nil,                     // nil = use the spec's
    // revision: omitted → ModelRevisionMap (vA.B for this SDK); ignored locally
    on_load_progress: nil                  // see "Load Progress" below
)
```

> `max_context_size` is deprecated and ignored — the KV-cache horizon comes
> from the bundle spec. It is still accepted so existing callers compile.

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

## Agent checklist

- Supported: Qwen3 / Gemma3 / LFM2.5 (see table).
- Chat template + stops come from the bundle — do not hardcode.
- Streaming chunks: drain `infer_stream`; check stop reason on final.
- Initialize before construct / `start_model`.
