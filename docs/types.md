# Inference types

The handful of types every pipeline shares: where the sampling knobs
live, what the timing fields mean, and how the same object looks in
Swift and in Flutter JSON. Each pipeline page documents its own config;
this page is the cross-reference.

> **Main features**
>
> - **One set of timing fields** on every result: how long the call took,
>   and where the time went.
> - **One `SamplingParams`** shared by LLM, VLM and TTS.
> - **Same names on both platforms**: a Swift field and its Flutter JSON
>   key are spelled the same.

## Timing fields

Every result carries these. Use them to show progress, to budget a
context window, or to spot a regression.

**Swift**

```swift
let llm = try await TSLLM(engines_path: "TheStageAI/Qwen3-0.6B")

let r = llm.infer(prompt: prompt, config: config)
// seconds until the first token
r.time_to_first_token
// decode speed
r.tokens_per_second
// wall time for the call
r.total_seconds
// what you sent
r.prompt_tokens
// what came back
r.generated_tokens
```

**Flutter**

```dart
final r = rows[0];
r['time_to_first_token'];
r['tokens_per_second'];
r['total_seconds'];
r['prompt_tokens'];
r['generated_tokens'];
```

| Field | Meaning |
|---|---|
| `total_seconds` | Wall time of the call. |
| `prefill_seconds` | Time to process the prompt (LLM / VLM) or the reference (TTS). For LLM this is the time to first token. |
| `decode_seconds` | Time generating tokens or audio frames. |
| `encode_seconds` | Vision encoder (VLM) or audio encoder (ASR). `0` for LLM / TTS. |
| `prompt_tokens` / `generated_tokens` | Sizes. ASR reports `0` prompt tokens. |
| `tokens_per_second` | Decode rate. |
| `rtf` (ASR, TTS) | Audio seconds per wall second. `20` means a minute of audio in three seconds. |

## Sampling

`SamplingParams` is the one place temperature and friends live. The LLM,
VLM and TTS configs all accept it; each pipeline also exposes the common
fields directly so you rarely construct it yourself.

**Swift**

```swift
let llm = try await TSLLM(engines_path: "TheStageAI/Qwen3-0.6B")

// Direct fields — the usual way
var config = llm.generation_defaults
config.temperature = 0.3
config.top_k = 20

// Or one object shared across pipelines
let sampling = SamplingParams(temperature: 0.7, top_k: 20)
let llmConfig = LLMGenerationConfig(sampling: sampling)
let ttsConfig = TTSGenerationConfig(sampling: sampling)
```

**Flutter**

```dart
// Flat keys in input_json — the usual way
{'prompt': prompt, 'temperature': 0.3, 'top_k': 20}
```

| Field | Meaning |
|---|---|
| `temperature` | `0` greedy and repeatable; higher is more varied. |
| `top_k` / `top_p` / `min_p` | Candidate filtering. Leave at the pack defaults unless tuning. |
| `repetition_penalty` | `> 1.0` discourages loops in long answers. |

Leaving a config empty keeps the pack's tuned values — `LLMGenerationConfig`
starts from the model's `generation_defaults`; `TTSGenerationConfig()`
leaves `sampling` unset so the voice's own defaults apply.

## Where each type lives

| Pipeline | Config | Result |
|---|---|---|
| LLM | `LLMGenerationConfig` — [LLM](./llm.md) | `LLMResult`; stream `LLMStreamChunk` / `LLMStreamEvent` |
| VLM | `LLMGenerationConfig` — [VLM](./vlm.md) | `LLMResult` (+ `encode_seconds`) |
| ASR | `ASRGenerationConfig`, `ASRStreamingConfig` — [ASR](./asr.md) | `ASRResult`; stream `ASRTurn` |
| TTS | `TTSGenerationConfig`, `TTSStreamConfig` — [TTS](./tts.md) | `TTSResult`; stream `InferenceStreamChunk` |
| Voice Agent | `TSAgentConfig` — [Voice Agent](./voice_agent.md) | typed channels + `TSAgentEvent` |

On Flutter the same types are plain maps with the same keys; the typed
Dart classes (`ASRGenerationConfig`, `TTSStreamConfig`, `LLMResult`, …)
are thin wrappers that serialise to exactly those keys.
