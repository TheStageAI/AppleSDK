# LLM (Language Model)

`TheStageLLM` runs Qwen3 / Gemma3 / LFM2.5 chat models fully on device:
tokenization, chat template, KV cache, sampling, stop policy, and token
streaming — all shipped in the engine bundle. Swift talks directly to
the class; Flutter goes through the singleton (`start_model` +
`infer` / `infer_stream`) using JSON payloads.

Use this pipeline for chat completions, streaming UIs, optional Qwen3
thinking, and Path A tool calling. Multi-turn state and tools also come
as `TheStageChatSession` from `llm.chat_session(...)`.

> **Main features**
>
> - **On-device chat**: Qwen3-0.6B, LFM2.5-230M / 350M, and Gemma3-1B —
>   no server round-trip, no per-token cost.
> - **Streaming and batch**: `llm.infer(...)` for a full reply,
>   `llm.infer_stream(...)` for token deltas on the same class.
> - **Path A tool calling**: pass `[Tool]` (with `execute` closures) and
>   the SDK runs each tool between turns on the **same** stream. Also
>   works with `DefaultTools.web` / `.phone` / `.voice`.
> - **`TheStageChatSession`**: multi-turn memory (sliding window / custom
>   policy), re-injected system prompt, and history that survives tool
>   rounds. Same object powers the Voice Agent local provider.
> - **Qwen3 thinking**: opt-in `<think>…</think>` prelude with a shared
>   `max_new_tokens` budget (`enable_thinking`).
> - **Deterministic seed**: same `seed` + `temperature = 0` + same
>   device+bundle → reproducible text (great for goldens).
> - **ANE-first placement**: per-component device overrides on the
>   bundle spec.

## In this page

Here we will cover the following topics:

- [**Supported models**](#supported-models): what ships, feature matrix, tool-calling caps.
- [**API surface**](#api-surface): Swift constructor / Flutter singleton, in one table.
- [**Quick start**](#quick-start): the shortest runnable Swift + Flutter example.
- [**Configuration**](#configuration): `LLMGenerationConfig` fields and their defaults.
- [**Streaming outputs**](#streaming-outputs): plain `LLMStreamChunk` and tool-aware `LLMStreamEvent` cases.
- [**Result object**](#result-object): `LLMInferenceResult` and its timing fields.
- [**Lifecycle**](#lifecycle): initialize → construct → infer → cleanup.
- [**Usage Guides**](#usage-guides): basic chat, multi-turn + tools, streaming to a UI, system prompts, thinking on/off, sampling recipes, seed, and stop reasons.
- [**Troubleshooting**](#troubleshooting): load failures, truncation, tool-JSON parse errors, wrong-language output, memory pressure.

## Supported models

| Model | HF repo | Size | Device | Fleet pin |
|-------|---------|-----:|--------|-----------|
| Qwen3-0.6B | `TheStageAI/Qwen3-0.6B` | 0.6B | NPU | v1.1 |
| LFM2.5-230M | `TheStageAI/LFM2.5-230M` | 230M | NPU | v1.1 |
| LFM2.5-350M | `TheStageAI/LFM2.5-350M` | 350M | NPU | v1.1 |
| Gemma3-1B | `TheStageAI/gemma-3-1b-it` | 1B | NPU | v1.1 |

| Feature | Qwen3-0.6B | LFM2.5-230M | LFM2.5-350M | Gemma3-1B |
|---------|:----------:|:-----------:|:-----------:|:---------:|
| Chat + streaming | yes | yes | yes | yes |
| Tool calling | yes | yes | yes | — |
| Thinking mode | yes | — | — | — |

Passing tools to a model where `supports_tool_calling` is `false` throws.
Context window is fixed per pack (not a public knob); prompt, history,
and new tokens share one window.

## API surface

| Purpose | Swift | Flutter |
|---------|-------|---------|
| Init | `try await TheStageLLM(engines_path:device:)` | `TheStageFlutterSDK.start_model(model_name:engines_path:)` |
| One-shot | `llm.infer(prompt:system_prompt:tools:config:)` | `TheStageFlutterSDK.infer(model_name:input_json:)` |
| Streaming (plain) | `llm.infer_stream(prompt:config:)` → `LLMStreamChunk` | `infer_stream(model_name:input_json:)` → `InferenceStreamChunk` |
| Streaming (tools / manual history) | `llm.infer_stream(messages:tools:)` → `LLMStreamEvent` | same JSON call with `tools` + `messages` |
| Chat session | `llm.chat_session(system_prompt:tools:memory:)` → `TheStageChatSession` | see the Voice Agent local Path A |
| Capabilities | `supports_tool_calling`, `tool_calling_format`, `generation_defaults` | mirrored via JSON metadata |
| Config | `LLMGenerationConfig` | same keys inside `input_json` |
| Progress | `on_load_progress` callback | `TheStageFlutterSDK.on_progress` |
| Cleanup | drop the object | `stop_model(model_name:)` |

## Quick start

**Swift:**

```swift
import TheStageSDK

try await TheStageAI.shared.initialize(apiToken: "your-api-token")

let llm = try await TheStageLLM(
    engines_path: "TheStageAI/Qwen3-0.6B",
    device: "npu"
)

var config = llm.generation_defaults
config.max_new_tokens = 128
config.enable_thinking = false

for await chunk in llm.infer_stream(
    prompt: "Give me a two-line haiku about the ocean.",
    system_prompt: "You are a concise assistant.",
    config: config
) {
    if !chunk.is_final { print(chunk.text, terminator: "") }
    else { print("\n\(chunk.tokens_per_second ?? 0) tok/s") }
}
```

**Flutter:**

```dart
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');
await TheStageFlutterSDK.start_model(
  model_name: 'llm',
  engines_path: 'TheStageAI/Qwen3-0.6B',
);

final stream = TheStageFlutterSDK.infer_stream(
  model_name: 'llm',
  input_json: {
    'prompt': 'Give me a two-line haiku about the ocean.',
    'system_prompt': 'You are a concise assistant.',
    'max_new_tokens': 128,
    'enable_thinking': false,
  },
);
await for (final chunk in stream) {
  if (chunk.isFinal) { print('done'); }
  else { stdout.write(chunk.delta); }
}
```

For multi-turn chat and Path A tools, use `TheStageChatSession`
(see [Usage Guides — multi-turn chat](#how-do-i-do-multi-turn-chat)).

## Configuration

`LLMGenerationConfig` (Swift) or the same keys inside `input_json`
(Flutter). Start from `llm.generation_defaults` and override only what
you need.

| Field | Default source | Notes |
|-------|----------------|-------|
| `max_new_tokens` | pack default | Hit → `stop_reason == max_new_tokens` |
| `temperature` | pack default | 0 = greedy |
| `top_k` | pack default | 0 = off |
| `top_p` | pack default | 1.0 = off |
| `min_p` | pack default | 0 = off |
| `repetition_penalty` | pack default | 1.0 = off |
| `enable_thinking` | pack default | Qwen3 only; ignored elsewhere |
| `seed` | random | Reproducible when inputs match |
| `min_new_tokens` | 0 | Swift only |

Chat template, EOS/stop tokens, and KV window are baked into the pack —
you do not set them. Thinking tokens count toward `max_new_tokens`.

## Streaming outputs

Plain stream (`LLMStreamChunk`):

| Field | Meaning |
|-------|---------|
| `text` | Token text (empty on final chunk) |
| `is_final` | Terminal chunk; carries metrics |
| `tokens_per_second` | Set on final chunk |

Tools / manual history stream (`LLMStreamEvent`, Swift):

| Case | Payload | UI meaning |
|------|---------|------------|
| `text_delta` | speakable text chunk | Append to assistant bubble |
| `tool_call` | `TheStageToolCall` | Show tool chip |
| `tool_result` | tool output for LLM | Silent (do not speak) |
| `final` | `LLMInferenceResult` + `stop_reason` | Turn done |

Flutter mirrors this shape via `input_json['tools']` and per-chunk
`kind` values.

## Result object

`LLMInferenceResult` (Swift) — mirrored in Flutter JSON:

| Field | Meaning |
|-------|---------|
| `text` | Raw decoded response |
| `tool_calls` | Parsed calls when tools were passed |
| `thinking` / `final_text` | Split when tools were parsed |
| `prompt_tokens` / `generated_tokens` | Token counts |
| `tokens_per_second` | Decode speed |
| `time_to_first_token` / `total_seconds` | Latency |
| `prefill_seconds` / `decode_seconds` | Phase timings |
| `stop_reason` | `eos` / `max_new_tokens` / `stop_sequence` / `unknown` |

## Lifecycle

1. `initialize(apiToken:)` once per process.
2. Construct `TheStageLLM` (or `start_model`) — first call downloads
   and compiles the pack. Subsequent calls are cheap.
3. Call `infer` / `infer_stream` / `chat_session` as needed.
4. Drop the object (Swift) or `stop_model` (Flutter) when done.

## Usage Guides

Jump to a recipe:

- [How do I run a basic chat completion?](#how-do-i-run-a-basic-chat-completion)
- [How do I do multi-turn chat?](#how-do-i-do-multi-turn-chat)
- [How do I stream to a chat UI?](#how-do-i-stream-to-a-chat-ui)
- [How do I set a system prompt?](#how-do-i-set-a-system-prompt)
- [How do I turn thinking on/off?](#how-do-i-turn-thinking-on-off)
- [How do I check if a model supports tool calls?](#how-do-i-check-if-a-model-supports-tool-calls)
- [How do I pass tools and read tool calls?](#how-do-i-pass-tools-and-read-tool-calls)
- [Sampling recipes](#sampling-recipes)
- [Deterministic seed](#deterministic-seed)
- [Reading stop_reason](#reading-stop-reason)

### How do I run a basic chat completion?

One-shot Q&A. Prefer the direct `TheStageLLM` constructor in Swift;
Flutter uses the JSON singleton.

**Swift:**

```swift
import TheStageSDK

let ai = TheStageAI.shared
try await ai.initialize(apiToken: "your-api-token")

let llm = try await TheStageLLM(
    engines_path: "TheStageAI/Qwen3-0.6B",
    device: "npu"
)

var config = llm.generation_defaults
config.max_new_tokens = 64
config.enable_thinking = false

let result = llm.infer(
    prompt: "What is 2+2?",
    system_prompt: "You are a helpful assistant.",
    config: config
)
print(result.text)
print(result.stop_reason)  // typically "eos"
```

**Flutter:**

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
    'enable_thinking': false,
  },
);
print(result[0]['text']);
```

Always call `initialize` before construct / `start_model`.

### How do I do multi-turn chat?

Batch `infer(prompt:...)` is **single-turn** — every call sees only
the prompt you passed, nothing you said before. Multi-turn state lives
in `TheStageChatSession`, which you get from
`llm.chat_session(system_prompt:tools:memory:)`.

The session owns:

- **Memory.** Sliding window by default (`memory: .SLIDING(max_turns: 10)`);
  pass `.NONE` to disable trimming or `.CUSTOM(...)` for your own
  policy.
- **System prompt.** Re-injected on every render — it does not consume
  a history slot and cannot fall off the window.
- **Tools.** When `tools: [Tool]` is non-empty the session runs Path A
  internally (see the tool-calling section below); tool rounds are
  stored so the next turn can reference them.
- **KV budget.** History is token-trimmed to fit the pack's context
  window (`fit_messages`) so small packs keep room to emit tool calls
  and completions.

**Swift — a full two-turn session, streaming both replies:**

```swift
import TheStageSDK

try await TheStageAI.shared.initialize(apiToken: "your-api-token")

let llm = try await TheStageLLM(
    engines_path: "TheStageAI/Qwen3-0.6B",
    device: "npu"
)

let session = llm.chat_session(
    system_prompt: "You are a friendly assistant. Answer in one sentence.",
    tools: [],                                 // no tools yet — pure chat
    memory: .SLIDING(max_turns: 10)
)

var config = llm.generation_defaults
config.max_new_tokens = 128
config.enable_thinking = false

// Turn 1 — the assistant learns the name.
session.add_text("My name is Ada.")
for await event in try session.submit_stream(config: config) {
    if case .text_delta(let t) = event { print(t, terminator: "") }
}
print()

// Turn 2 — no need to re-pass history; the session tracked it.
session.add_text("What is my name?")
for await event in try session.submit_stream(config: config) {
    if case .text_delta(let t) = event { print(t, terminator: "") }
}
print()

// Inspect what the session kept — user/assistant turns, plus tool
// rounds if tools fired. `text_content` flattens all TEXT parts.
for m in session.history { print(m.role, m.text_content) }
```

**Swift — same session, with Path A tools.** The only change from the
plain chat example is `tools:`; the session runs `Tool.execute`
between turns and stashes both the tool call and the tool result in
history.

```swift
let toolSession = llm.chat_session(
    system_prompt: DefaultTools.voice_system_prompt,
    tools: DefaultTools.web,                    // get_weather, web_search, …
    memory: .SLIDING(max_turns: 10)
)

toolSession.add_text("What's the weather in Paris?")
for await event in try toolSession.submit_stream(config: config) {
    switch event {
    case .text_delta(let t):
        print(t, terminator: "")                // speakable answer
    case .tool_call(let call):
        print("\n[tool→ \(call.name)(\(call.arguments))]")
    case .tool_result(let name, let content):
        print("[tool← \(name): \(content.prefix(80))…]")
    default:
        break
    }
}
```

Voice Agent local Path A uses the same session under
`TheStageLocalLLMProvider` — see [voice agent](./voice_agent.md).

**Flutter / JSON** — no session façade yet; pass `messages` on
**`infer_stream`** (batch `infer` still uses `prompt` only) and keep
history in the app:

```dart
final stream = TheStageFlutterSDK.infer_stream(
  model_name: 'llm',
  input_json: {
    'messages': [
      {'role': 'user', 'content': 'My name is Ada.'},
      {'role': 'assistant', 'content': 'Nice to meet you, Ada.'},
      {'role': 'user', 'content': 'What is my name?'},
    ],
    'system_prompt': 'You are a helpful assistant.',
    'max_new_tokens': 128,
    'enable_thinking': false,
  },
);

final buf = StringBuffer();
await for (final chunk in stream) {
  if (chunk['is_final'] == true) break;
  final delta = chunk['delta'] as String?;
  if (delta != null) buf.write(delta);
}
print(buf.toString());
```

**Low-level Swift** (manual history): `llm.infer_stream(messages:)` with
`[ChatTemplate.Message]` — you own append/trim; no automatic tool-round
memory.

### How do I stream to a chat UI?

Each non-final `LLMStreamChunk` carries `text` to append. The final
chunk has `is_final == true` and per-call metrics — read
`tokens_per_second` / `stop_reason` only there. Flutter JSON uses
`delta` instead of `text`.

**Swift:**

```swift
var config = llm.generation_defaults
config.max_new_tokens = 512
config.enable_thinking = false

for await chunk in llm.infer_stream(
    prompt: "Tell me a story.",
    config: config
) {
    if chunk.is_final {
        let tps = chunk.tokens_per_second ?? 0
        print("\n--- \(tps) tok/s stop=\(chunk.stop_reason ?? "?") ---")
    } else {
        print(chunk.text, terminator: "")  // append to UI
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
    'enable_thinking': false,
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

Drain the stream fully — dropping the consumer can stall generation.

### How do I set a system prompt?

`system_prompt` shapes tone and constraints. If omitted, the bundle’s
default system prompt is used. System text consumes context tokens —
keep it short.

**Swift:**

```swift
var config = llm.generation_defaults
config.max_new_tokens = 256
config.enable_thinking = false

let result = llm.infer(
    prompt: "How do I make risotto?",
    system_prompt:
        "You are a cooking assistant. Only answer questions about recipes.",
    config: config
)
print(result.text)
```

**Flutter:**

```dart
final result = await TheStageFlutterSDK.infer(
  model_name: 'llm',
  input_json: {
    'prompt': 'How do I make risotto?',
    'system_prompt':
        'You are a cooking assistant. Only answer questions about recipes.',
    'max_new_tokens': 256,
    'enable_thinking': false,
  },
);
```

Works with both `infer` and `infer_stream`.

### How do I turn thinking on/off?

Qwen3 reasons by default and can emit a `<think>…</think>` prelude
before the visible answer. Pass `enable_thinking: false` to inject an
empty pre-closed think block (HF-compatible) so the model skips
reasoning. Gemma / LFM ignore the flag.

Thinking tokens still count toward `max_new_tokens` — budget headroom
when thinking is on. With thinking off, short chat replies avoid an
empty-looking “blank” prelude in the UI (strip or hide `<think>` if you
ever leave thinking on and render raw `text`).

**Thinking off (typical chat UX):**

```swift
var config = llm.generation_defaults
config.max_new_tokens = 256
config.enable_thinking = false

let result = llm.infer(
    prompt: "What is the capital of France?",
    config: config
)
print(result.text)  // direct answer, no <think> block
```

**Thinking on (harder reasoning):**

```swift
var config = llm.generation_defaults
config.max_new_tokens = 1024
config.temperature = 0.6
config.enable_thinking = true

let result = llm.infer(
    prompt: "Explain why the sky appears blue.",
    config: config
)
// result.text may start with <think>…</think> then the answer
print(result.text)
```

### How do I check if a model supports tool calls?

See the Features table above, or ask the loaded model:

```swift
if llm.supports_tool_calling {
    // safe to pass tools:
} else {
    // chat-only pack (e.g. Gemma3-1B) — tools: throws
}
```

Optional diagnostics: `llm.tool_calling_format` / `llm.tool_calling_spec`
(wire style for supported packs).

### How do I pass tools and read tool calls?

Preferred API: **`Tool`** (JSON schema + `execute` in one object) or the
built-in **`DefaultTools`** catalog. The stream is tag-aware:
`LLMStreamEvent` (`text_delta`, `tool_call`, `tool_result`, `final`).
Wire markup differs by pack; you always get parsed
`ToolCall { name, arguments }`.

Gemma3-1B has no tools in this fleet — use Qwen3 or LFM2.5.
(`LLMToolDefinition` / `LLMToolCalling` are deprecated aliases of
`ToolDefinition` / `ToolCalling`.)

| Path | API | Who runs tools |
|------|-----|----------------|
| **A (preferred)** | `infer_stream(..., tools: [Tool])` | SDK runs each `Tool.execute`, emits `tool_result`, continues on the **same** stream (up to `max_tool_rounds`, default **4**) |
| **B (manual)** | `infer_stream(..., tools: [ToolDefinition], executor: nil)` | Stream ends after the tool turn; you run tools and call `infer_stream` again |

**Path A does not close the stream on a tool call.** Decode pauses when a
ready `tool_call` arrives, the SDK runs `Tool.execute`, then starts the
next model turn and keeps yielding on that **same** `for await`. Your
loop stays one elegant consumer:

```text
for await event in infer_stream(tools: [Tool])   // one loop
   text_delta "Okay, let me check…"              ← speak
   tool_call  →  (SDK runs Tool.execute)  →  tool_result
   text_delta "It's 18°C in Paris."              ← speak
   final                                         ← only here does the stream end
```

**Path A — built-in catalog (shortest)**

```swift
var config = llm.generation_defaults
config.max_new_tokens = 256
config.enable_thinking = false

for await event in try llm.infer_stream(
    prompt: "What time is it in Tokyo, and what's the weather?",
    tools: DefaultTools.web,   // or .voice / .phone / cherry-pick
    system_prompt: DefaultTools.voice_system_prompt,
    config: config
    // max_tool_rounds: 4   // optional; SDK stops tool loops here
) {
    if case .text_delta(let t) = event {
        print(t, terminator: "")   // UI / TTS
    }
}
```

| Subset | Tools |
|--------|--------|
| `DefaultTools.voice` (alias `.all`) | `web` + `phone` — recommended for voice |
| `DefaultTools.web` | `get_weather`, `get_local_time`, `web_search`, `wikipedia_summary`, `calculate` |
| `DefaultTools.phone` | `open_url`, `dial_phone`, `open_maps`, `compose_sms`, `compose_email`, `copy_to_clipboard`, `get_battery` |

Phone tools open system UI (`mailto:` / `sms:` / `tel:` / Maps) — the user
confirms Send/Call. Every tools system prompt includes
`ToolCalling.spoken_before_tools_instruction` (short filler before a call).

**Path A — custom `Tool`**

```swift
func get_weather(_ call: ToolCall) async throws -> String {
    let city = call.arguments["city"] as? String ?? ""
    return #"{"city":"\#(city)","temp_c":18,"condition":"cloudy"}"#
}

let tools = [
    Tool(
        name: "get_weather",
        description: "Get the current weather for a city.",
        parameters: [
            "type": "object",
            "properties": [
                "city": ["type": "string", "description": "City name"],
            ],
            "required": ["city"],
        ],
        execute: get_weather   // omit → mock {"status":"tool executed",…}
    ),
]

for await event in try llm.infer_stream(
    prompt: "What's the weather in Paris?",
    tools: tools,
    config: config
) {
    if case .text_delta(let t) = event { print(t, terminator: "") }
}
```

Lower-level split still works: `ToolDefinition` + `MapToolExecutor` via
`infer_stream(..., tools:definitions, executor:)`.

Demo: `(SDK internals)` (`TOOL_MODE=executor|web|voice`).

**Path B — only if you cannot use `Tool.execute` (e.g. Flutter)**

On Swift you almost never need this: Path A does the same steps inside
the SDK. Path B is “definitions only, no executor” — **you** are the
executor:

```text
1) infer_stream(definitions, executor: nil)
      → model may emit tool_call(s)
2) you run get_weather / … yourself
3) append assistant raw + ToolCalling.tool_message(result)
4) infer_stream again → spoken answer
```

Flutter / singleton can only do Path B today: pass `tools` as definition
maps in `input_json`, handle `tool_call` events in Dart, append
`{role: tool, content: …}`, call `infer_stream` again.

**Batch:** `infer(prompt:tools:)` → `result.tool_calls` / `result.final_text`.
With handlers: `await infer(prompt:tools: [Tool])` (Path A).

**Voice Agent:** stock provider is tool-less — see
[Voice Agent — tools](./voice_agent.md#how-do-i-add-tool-calling-to-a-voice-app).
Custom provider: Path A with `DefaultTools.voice`, yield **only**
`text_delta` into TTS.

### Sampling recipes

Copy a block that matches the product job. Values are starting points —
tune on device.

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

Check `result.stop_reason`. If it is `"max_new_tokens"`, raise the cap
and retry.

**4. Hard reasoning (Qwen3 thinking)**

```swift
var config = llm.generation_defaults
config.max_new_tokens = 1024
config.temperature = 0.6
config.enable_thinking = true
```

### Deterministic seed

For tests and golden fixtures, set `seed` (and usually
`temperature = 0`). Same seed is only guaranteed on the **same device +
same bundle revision**.

```swift
var config = llm.generation_defaults
config.temperature = 0
config.seed = 42
config.max_new_tokens = 64
config.enable_thinking = false

let a = llm.infer(prompt: "Write a haiku about the ocean.", config: config)
let b = llm.infer(prompt: "Write a haiku about the ocean.", config: config)
// a.text == b.text on the same device + bundle
```

```dart
input_json: {
  'prompt': 'Write a haiku about the ocean.',
  'seed': 42,
  'temperature': 0,
  'max_new_tokens': 64,
  'enable_thinking': false,
}
```

### Reading stop_reason

| `stop_reason` | Meaning | UX |
|---|---|---|
| `"eos"` | Model finished naturally | Show full reply |
| `"max_new_tokens"` | Hit the length cap | Mark truncated; raise cap and retry |
| `"stop_sequence"` | Hit a configured / template stop | Usually complete enough |
| `"unknown"` | Unexpected end | Log metrics; treat as incomplete |

```swift
let result = llm.infer(prompt: "Explain quantum computing.", config: config)
switch result.stop_reason {
case "eos":
    break
case "max_new_tokens":
    // raise config.max_new_tokens and retry, or show "continued…"
    break
default:
    break
}
```

On streams, read `stop_reason` from the **final** chunk after draining.

## Troubleshooting

### Model loading fails or hangs

1. Confirm `TheStageAI.shared.initialize(apiToken:)` (or Flutter
   `initialize`) completed before construct / `start_model`.
2. First launch needs network to download the HF pack — check
   connectivity.
3. Attach `on_load_progress` (or Flutter `on_progress`) to see the stuck
   phase (`.downloading` → network; `.loading` → often RAM).

### Response is cut off mid-sentence

1. Check `stop_reason` — `"max_new_tokens"` means raise the cap.
2. Multi-turn: trim history so prompt + reply fit the pack’s context
   window.
3. With thinking on, increase `max_new_tokens` — think tokens share the
   budget.

### Thinking makes replies slow or empty-looking

1. Set `enable_thinking = false` for short chat UX.
2. If thinking stays on, strip or hide `<think>…</think>` in the UI
   before showing `final` text (`result.thinking` /
   `result.final_text` when tools were passed).
3. Raise `max_new_tokens` when reasoning is required.

### Tool JSON parse failures / truncated `<tool_call>`

1. Confirm `supports_tool_calling` and use the public tool API only.
2. Prefer temperature 0, short tool list; Qwen3: thinking off for demos.
3. If `stop_reason == "max_new_tokens"`, the call may be truncated —
   raise the cap.
4. Empty `result.tool_calls` with junk in `result.text` → log and retry.

### Wrong language or garbled output

1. Lower temperature (factual recipe) or start from
   `generation_defaults`.
2. Do not paste `<|im_start|>` / other template tokens into `prompt` —
   the SDK applies the chat template once.
3. Confirm `engines_path` points at a TheStageAI shipping bundle.

### Out of memory / device fallback

1. Switch to a smaller pack (**LFM2.5-230M** or **Qwen3-0.6B**).
2. Prefer `device: "npu"`; stop other heavy pipelines (ASR / TTS / VLM)
   before loading.
3. `max_context_size` does not shrink RAM — horizon is fixed by the
   bundle.

### Flutter JSON key mismatches

1. Read `result[0]['text']` (not a top-level string).
2. Streaming deltas are under `chunk['delta']`; metrics on
   `is_final == true`.
3. Multi-turn: send `messages` on **`infer_stream`**, not batch
   `infer`.
4. `min_new_tokens` is Swift-only — omit it from `input_json`.

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
