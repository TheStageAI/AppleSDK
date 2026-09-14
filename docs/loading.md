# Loading models — `load_models`, warm-up, and staying specialized

Everything an app needs to get a known set of models ready is one call. The voice
agent uses it for its own stack; an app that runs several models (chat, notes,
voice) calls it with the set it needs, in the order it needs them.

## `load_models`

```swift
let stack: [TSModelStartRequest] = [
    .init(handle: "stt", path: "TheStageAI/thewhisper-large-v3-turbo",
          model_type: "thestage_asr", eviction_priority: .PINNED),
    .init(handle: "llm", path: "TheStageAI/LFM2.5-350M", model_type: "thestage_llm"),
    .init(handle: "tts", path: "TheStageAI/Qwen3-TTS-12Hz-0.6B-Base",
          model_type: "thestage_tts", required: false),
]
let statuses = try await TheStageAI.shared.load_models(stack) { progress in
    // progress.model is the handle; progress.phase is downloading / extracting /
    // loading / ready. The last event is (model: "sequence", phase: .ready).
}
```

`TSModelStartRequest` is the `start_model` argument set plus two flags:

| field | default | meaning |
|---|---|---|
| `required` | `true` | a failed required model aborts the sequence; a non-required one is reported `failed` and the rest continue |
| `warmup` | `true` | run the model once after loading, so it is specialized before the first request |

After `load_models` returns, every handle answers `start_model` immediately (it is
already running) and its first inference costs no compilation.

## What one call guarantees

1. **One copy per bundle on disk.** A model lives once under the SDK's
   Application Support folder, encrypted, with its keys in the Keychain. The
   downloaded archive is deleted when the model is promoted; nothing is kept twice.
2. **No member of the sequence is unloaded to load the next.** The set is admitted
   as a whole; if memory is short you are told before anything downloads.
3. **Loaded means specialized.** Warm-up runs every engine once, so the Neural
   Engine programs are compiled and cached before your first request, and the
   cache entries are saved so they survive an OS cache purge.
4. **Progress per model**, then one final `ready` for the sequence.

## Downloads

Pass your Hugging Face token once at init; the SDK sends it only to the Hub and
strips it on CDN redirects. Public models download without a token.

```swift
try await TheStageAI.shared.initialize(api_token: sdkToken, hf_token: hfToken)
```

## Staying specialized

iOS clears `Caches/` under storage pressure, which throws away the Neural Engine
programs; the next start would then specialize for tens of seconds. The SDK can
tell you before your user finds out:

```swift
let health = try await TheStageAI.shared.specialization_health(for: stack)
// .warm                    nothing to do
// .purged(restored: n)     the cache was wiped; n tickets were put back — starts stay warm
// .cold(models: [handles]) these models must specialize again

// From a BGProcessingTask (charger + idle), or after an app update:
try await TheStageAI.shared.respecialize_if_needed(stack)   // load_models for the cold ones, then stop
```

A small app-side keeper is enough: check `specialization_health` when the app comes
to the foreground (it costs one tiny engine load), and when it reports `.cold`
schedule a `BGProcessingTask` with `requiresExternalPower = true` that calls
`respecialize_if_needed`. Register the task's launch handler before the app
finishes launching.

## One model at a time

`start_model` is still there for a single model and goes through the same path:

```swift
let llm = try await TheStageAI.shared.start_model(
    TSLLM.self, model_name: "llm", engines_path: "TheStageAI/LFM2.5-350M",
    model_type: "thestage_llm"
)
```

Hold the returned pipeline; it is the object you infer with.

Where each engine runs is decided by the SDK: model engines on the Neural
Engine, spectrogram front ends on the CPU. There is nothing to configure.
