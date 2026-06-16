# Voice Agent

End-to-end on-device voice assistant: VAD → STT → LLM → TTS, with
neural end-of-turn detection (the **smart-turn-v3** model), interruption
handling, streaming transcription (live partial captions), and
sentence-level streaming for sub-second time-to-first-audio.

## Quick Start (Swift)

```swift
import TheStageSDK

let ai = TheStageAI.shared
try await ai.initialize(apiToken: "your-api-token")

let llm = TheStageOpenAICompatibleProvider(
    endpoint: "https://api.openai.com/v1/chat/completions",
    api_key: "sk-...",
    model: "gpt-4o-mini"
)

var config = TheStageAgentConfig(
    vad: "TheStageAI/silero-vad",
    stt: "TheStageAI/thewhisper-large-v3-turbo",
    tts: "TheStageAI/neutts-multilingual",
    llm: llm
)
config.system_prompt = "You are a helpful voice assistant. Keep replies short."

let agent = TheStageVoiceAgent(config: config)

// Legacy event stream (state changes, transcripts, deltas, errors).
Task {
    for await event in agent.events {
        switch event.kind {
        case .state_changed:    print("[STATE] \(event.data["state"] ?? "?")")
        case .user_request:     print("[YOU] \(event.data["text"] ?? "")")
        case .response_delta:   print(event.data["delta"] ?? "", terminator: "")
        case .response_done:    print("\n[ASSISTANT DONE]")
        case .error:            print("[ERROR] \(event.data["message"] ?? "")")
        default: break
        }
    }
}

// New typed channels: subscribe as many independent receivers as you want.
// `recv()` returns an `AsyncStream` per subscriber; sending is fan-out.
Task {
    for await delta in agent.llm_deltas.recv() {
        // Append delta to a chat bubble, etc.
    }
}

try await agent.start()
// agent runs continuously — speak into the mic
```


## Quick Start (Flutter)

```dart
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

final agent = TheStageVoiceAgentFlutter();

agent.events.listen((event) {
  switch (event['kind']) {
    case 'state_changed': print('STATE: ${event['state']}');
    case 'user_request':  print('YOU: ${event['text']}');
    case 'response_delta': stdout.write(event['delta']);
    case 'response_done': print('\nASSISTANT DONE');
  }
});

// Typed broadcast streams (one EventChannel each, fan-out in Swift).
agent.llmDeltas.listen((delta) => /* update assistant bubble */);
agent.transcripts.listen((text) => /* show user turn */);
agent.vadProbabilities.listen((p) => /* drive a level meter */);

await agent.start(config: {
  'vad': 'TheStageAI/silero-vad',
  'stt': 'TheStageAI/thewhisper-large-v3-turbo',
  'tts': 'TheStageAI/neutts-multilingual',
  'llm_provider': 'openai_compatible',
  'llm_endpoint': 'https://api.openai.com/v1/chat/completions',
  'llm_api_key': 'sk-...',
  'llm_model': 'gpt-4o-mini',
  'system_prompt': 'You are a helpful voice assistant.',
});

// Later:
await agent.interrupt();          // stop current response
await agent.say('Welcome back!'); // speak arbitrary text (skips LLM)
await agent.updateInterruptConfig(interruptMinSpeechMs: 200);
await agent.stop();
```

## State Machine

```
                     ┌────────────────────────────────────────┐
                     │  if config.wake_word == nil            │
idle → loading ─────►│  listening ⇄ thinking → speaking       │──► listening
                     │                                        │
                     │  else (wake-word configured)           │
                     │  sleeping ─WW─► listening ⇄ thinking   │──► speaking ──► sleeping
                     └────────────────────────────────────────┘
```

| State | Meaning |
|-------|---------|
| `idle` | Models not loaded |
| `loading` | Models being downloaded / loaded |
| `sleeping` | Wake-word standby. VAD/WW are live, ASR/LLM/TTS are gated off. Only entered when `wake_word` is configured. |
| `listening` | Mic open, VAD scanning for speech |
| `thinking` | Speech committed, LLM is generating |
| `speaking` | TTS streaming audio to the speaker |

State is derived inside `AgentOrchestrator` from the event stream and is
the only place the state machine lives. It is broadcast as
`AgentEvent.STATE(_)` and surfaces on the public stream as the
`state_changed` event.

## Public Output Channels

In addition to the legacy `events` stream, the agent exposes three typed
fan-out ports. Each `recv()` returns an independent `AsyncStream` that
sees every value — perfect for plugging UI widgets, log taps and
speech-to-file recorders side-by-side without intermediate bookkeeping.

| Property | Type | What it carries |
|----------|------|-----------------|
| `agent.llm_deltas` | `AgentChannel<String>` | Each LLM token delta as it is generated, in order |
| `agent.partial_transcripts` | `AgentChannel<String>` | Stable partial transcripts *while the user speaks* — committed-so-far text, monotonically growing within a turn. Empty when `asr_streaming` is off. Great for live captions. |
| `agent.transcripts` | `AgentChannel<String>` | One value per user turn (the finalized Whisper transcript; empty on aborted turns) |
| `agent.vad_probabilities` | `AgentChannel<Double>` | Per-frame Silero probability ([0, 1]); roughly one value every 32 ms |

```swift
let level_tap = AgentConnector(from: agent.vad_probabilities) { prob in
    DispatchQueue.main.async { meter.value = prob }
}
// ...later
level_tap.disconnect()
```

`AgentConnector` is the convenience for "do something on each value
without writing the `for await` boilerplate"; if you need the stream
directly, just call `agent.vad_probabilities.recv()`.

The same channels are exposed in Flutter as
`agent.llmDeltas` (`Stream<String>`), `agent.transcripts`
(`Stream<String>`), and `agent.vadProbabilities` (`Stream<double>`),
each backed by its own `EventChannel`.

## Configuration

### Models

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `vad` | String | required | HF id or local path of Silero VAD bundle |
| `stt` | String | required | HF id or local path of Whisper bundle |
| `tts` | String? | `nil` | HF id or local path of NeuTTS bundle (required to speak) |
| `tts_voice` | String | `"paul"` | Voice preset id |
| `wake_word` | String? | `nil` | Optional wake-word bundle. When set, the agent rests in `.sleeping` until the wake word fires. |
| `stt_language` | String | `"en"` | Whisper decode language (ISO-639-1, e.g. `"en"`, `"es"`) |
| `stt_revision` | String | `"develop"` | HF branch / tag for STT |
| `tts_revision` | String | `"develop"` | HF branch / tag for TTS |

### Compute device routing (Apple Silicon)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `vad_device` | String | `"npu"` | Silero VAD compute device |
| `stt_device` | String | `"npu"` | Whisper coarse default |
| `stt_devices` | `[String:String]?` | `nil` | Per-module override: `melspec`, `encoder`, `decoder` |
| `tts_device` | String | `"npu"` | NeuTTS coarse default |
| `tts_devices` | `[String:String]?` | `nil` | Per-module override: `llm`, `neucodec` |
| `ww_device` | String | `"npu"` | Wake-word compute device |

NPU is the default because:

- ANE has its own dedicated tensor memory pool — no FP16 weight
  decompression buffer like on GPU. STT cold start dropped from
  ~6.7 s (GPU) to ~170 ms (NPU) on M-class hardware.
- The NPU keeps running when the app is in the background; GPU
  compute can be throttled or denied by the OS.

### LLM

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `llm` | `TheStageLLMProvider` | required | Local or remote LLM (Swift API) |
| `llm_provider` | String | required | `"local"` or `"openai_compatible"` (Flutter) |
| `system_prompt` | String | helpful default | Prepended as a system message |
| `max_tokens` | Int | 256 | Generation cap |
| `temperature` | Double | 0.7 | Sampling temperature |
| `chat_memory` | `TheStageChatMemory` | `TheStageSlidingWindowMemory(max_turns: 10)` | History strategy |

### VAD / endpointing

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `vad_threshold` | Double | 0.8 | Speech probability threshold |
| `vad_onset_ms` | Int | 96 | Sustained voiced duration to trigger onset |
| `silence_timeout_ms` | Int | 608 | Trailing silence to commit turn |
| `max_accumulation_ms` | Int | 30000 | Hard cap on a single turn |
| `pre_roll_ms` | Int | 200 | Pre-roll captured before onset |

All durations are in **milliseconds**; the nodes convert them to the live VAD
frame cadence (`frame_samples / sample_rate`, ≈32 ms for Silero @ 16 kHz)
internally. `silence_timeout_ms` only applies to the default VAD endpointer
(`turn_detection_mode == .vad`); the DNN endpointer ignores it.

### Turn detection (end-of-turn)

The endpointer is pluggable behind the `TurnNode` protocol. `.vad` (default)
commits a turn after a fixed silence gap (`silence_timeout_ms`). `.dnn`
replaces that with the pipecat **smart-turn-v3** model: at each pause it runs
a learned end-of-turn check on the trailing waveform, so the agent waits
through mid-sentence pauses but responds quickly once you're actually done.

VAD is the cheap gate (onset + pause detection); the DNN is the expensive
semantic check run **single-flight, off-thread, only at pauses**, with a hard
`turn_max_silence_ms` floor so it can never hang or classify an empty
window. The model sees the **continuous** waveform from onset (incl. pre-roll)
through the pause — never VAD-filtered audio.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `turn_detection_mode` | enum | `.vad` | `.vad` (silence timeout) or `.dnn` (smart-turn model) |
| `turn_detector` | String? | `nil` | smart-turn engines repo/path (required for `.dnn`), e.g. `"TheStageAI/smart-turn-v3"` |
| `turn_detector_revision` | String | `"main"` | HF branch / tag for the smart-turn engines |
| `turn_detector_device` | String | `"npu"` | Compute device for the classifier (int8, ANE) |
| `turn_eot_threshold` | Double | 0.85 | Completion prob at/above which a checkpoint counts as "done" |
| `turn_eot_confirm_count` | Int | 2 | Consecutive "done" verdicts required before committing. Debounces a single spike on a mid-sentence pause. `1` = fire on first positive. |
| `turn_eot_high_confidence` | Double | 1.0 | Verdict prob that commits immediately, skipping confirmation. `>= 1.0` (default) disables the bypass (see note). |
| `turn_pause_trigger_ms` | Int | 256 | Trailing silence before the first model call |
| `turn_reeval_interval_ms` | Int | 120 | Re-run cadence on a sustained pause (0 disables) |
| `turn_max_silence_ms` | Int | 5000 | Hard fallback; MUST be < `turn_window_ms` |
| `turn_window_ms` | Int | 8000 | Trailing audio window fed to the model |
| `turn_min_speech_ms` | Int | 250 | Minimum voiced speech before the model is consulted |
| `turn_asr_silence_hangover_ms` | Int | 200 | Trailing silence still fed to streaming ASR after speech stops (bounds "mm"/"?" filler; the turn model still sees the full pause) |

```swift
var config = TheStageAgentConfig(vad: ..., stt: ..., tts: ..., llm: ...)
config.turn_detection_mode = .dnn
config.turn_detector = "TheStageAI/smart-turn-v3"   // or a local .zip / dir
```

The model is a two-module CoreML chain: an fp32 mel front-end (CPU/GPU) feeding
an int8-weight Whisper-Tiny encoder + completion head (ANE), shipped as
`TheStageAI/smart-turn-v3` and downloaded/cached by the SDK on first use.
Knobs hot-apply at runtime via `agent.update_turn_config(...)`.

**Why a confirm count.** A single model checkpoint can spike over
`turn_eot_threshold` on a brief mid-sentence pause. Requiring
`turn_eot_confirm_count` consecutive "done" verdicts (re-evaluated every
`turn_reeval_interval_ms`) debounces that, at the cost of a little latency.
The `turn_eot_high_confidence` fast-path (commit immediately on a very
confident single verdict) is **off by default** (`1.0`): the eval harness
showed it commits before enough trailing silence is buffered and clips the
last ASR word, even on 0.99-confident verdicts. Lower it (e.g. `0.97`) only
if you measure that it doesn't truncate finals on your audio.

### Streaming transcription (ASR)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `asr_streaming` | Bool | `true` | Emit live partial captions (`user_request_partial`) while the user speaks. Purely cosmetic — the authoritative transcript is identical whether this is on or off. |
| `asr_partial_interval_ms` | Int | 600 | Minimum new audio between caption passes (bounds redundant decoding). Streaming only. |
| `speculative_whisper` | Bool | `true` | Decode a speculative full-utterance pass at the first VAD pause so the final transcript is warm by end-of-turn (low-latency final). |
| `asr_sentence_flush` | Bool | `true` | **Deprecated / no-op.** Retired from the agent path; kept for source compatibility. |
| `asr_max_segment_seconds` | Double | 12.0 | **Deprecated / no-op.** Retired from the agent path; kept for source compatibility. |

The `ASRNode` runs **one unified path** with two decoupled consumers that
share a **single serial inference chain** (the model is never entered
concurrently):

- **Captions (cosmetic).** When `asr_streaming` is on, the node re-decodes
  the growing turn buffer every `asr_partial_interval_ms` (a VAD pause
  forces a pass early) and folds the result through **LocalAgreement-2**:
  only the prefix two consecutive hypotheses agree on is surfaced, so
  captions never flicker or retract. Committed text is published as
  `USER_REQUEST_PARTIAL` (→ `agent.partial_transcripts` / the
  `user_request_partial` event). These partials never feed the LLM.
- **Authoritative.** At `end_of_turn` the node emits exactly one
  `USER_REQUEST(.speech)`. It reuses the most recent full-buffer decode
  (a caption or the speculative pass) when the buffer hasn't drifted past
  `speculative_max_drift_samples`; otherwise it decodes the whole buffer
  fresh. This is the **only** value that drives the LLM.

This split is the fix for the old "pause mangles the transcript" bug: a
VAD pause (`VoiceChunk.speculate`) only nudges a caption refresh / primes
the speculative final — it never segments, trims, or finalizes the
authoritative result. Because the authoritative decode is always a single
full-utterance pass, **both modes produce identical final text**;
`asr_streaming` only decides whether live captions are emitted along the
way. The old sentence-gated buffer-trimming path (`asr_sentence_flush` /
`asr_max_segment_seconds`) is retired — those fields are now no-ops kept
only so existing call sites still compile.

When `asr_streaming` is off, no caption passes run; the speculative pass
(if `speculative_whisper`) still warms the final at the VAD pause, so
perceived STT latency stays near **0 ms** in the steady state. The handoff
is in-band: the turn node pushes `VoiceChunk.speculate` / `.end_of_turn`
markers on the same wire that carries voiced frames, so finalization stays
in lock-step with the audio (no cross-channel race).

`ASRStreamer` / `TheStageASRStreamingSession` remain the reusable,
push-based engine (`send` audio → read `partials` → `finish`) behind
`WhisperPipeline.open_streamer(...)` for direct, non-agent callers; the
agent's `ASRNode` no longer uses it but it is otherwise untouched.

### Interruption / AEC

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `interrupt_mode` | `InterruptTrigger` | `.speech_only` (iOS) / `.none` (macOS) | How (and whether) the user can barge in |
| `allow_interruptions` | Bool | computed | Back-compat alias: `true` ⇔ `interrupt_mode != .none` |
| `interrupt_min_speech_ms` | Int | 600 | Sustained speech needed to interrupt (Flutter slider goes down to 100 ms) |
| `interrupt_onset_ms` | Int | 0 | Sustained positive-VAD duration to fire a barge-in. When `> 0` it takes precedence over `interrupt_min_speech_ms`. |
| `interrupt_threshold` | Double | 0.9 | VAD prob threshold for barge-in, independent of `vad_threshold`. Kept strict so the agent doesn't trip on its own TTS / AEC residue. |
| `interrupt_min_playback_ms` | Int | 250 | Grace at TTS turn start during which barge-in is suppressed (lets AEC re-converge) |
| `interrupt_initial_lockout_ms` | Int | 1000 | One-time, longer barge-in lockout on the *first* TTS playback after start (covers iOS VPIO cold-start). Should exceed `aec_warmup_ms`. |
| `interrupt_thinking_lockout_ms` | Int | 600 | Barge-in lockout while `.thinking` (mic live, AEC has no reference yet). 0 disables. |
| `aec_enabled` | Bool | `true` | Voice Processing IO (iOS only — set `false` on macOS) |
| `aec_warmup_ms` | Int | 250 | Silence pumped to the speaker on start so VPIO has reference samples |
| `aec_playback_gate_tail_ms` | Int | 80 | Sink-drain grace at end of every TTS turn |

```swift
public enum InterruptTrigger: String, Sendable {
    case none         // Never interrupt; AudioEngineNode hard-mutes the mic during playback.
    case speech_only  // Sustained user speech is enough to barge in.
    case wake_word    // Wake word must fire during sustained speech to confirm interrupt.
}
```

`.none` is the default on macOS because no Voice Processing IO is
available there — without AEC the agent would otherwise hear its own
TTS output and barge in on itself. With `.none` the audio engine drops
mic samples while the speaker is playing, so VAD never sees the
self-echo.

### Wake-word standby

When `wake_word` is set, the orchestrator's resting state is
`.sleeping`: VAD still runs, and `WakeWordNode` classifies the same
voiced-audio fan-out wire that feeds STT. Only `WAKE_WORD_DETECTED`
flips the agent to `.listening`. After a turn finishes (or is
interrupted) the agent returns to `.sleeping`.

When `wake_word` is `nil`, `.sleeping` is never entered and the resting
state between turns is `.listening`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `wake_word` | String? | `nil` | HF id or local path of the wake-word bundle. Enables `.sleeping` standby. |
| `ww_threshold_score` | Double | 0.5 | Probability the wake-word classifier must reach for a positive detection. Tune per model. |
| `ww_device` | String | `"npu"` | Wake-word compute device (see compute routing). |

## Events

The agent emits a modality-agnostic, lifecycle-oriented event vocabulary.
Each event is `{ kind, data }`:

| `kind` | `data` keys | When |
|--------|-------------|------|
| `state_changed` | `state` | State transition |
| `user_request_partial` | `text` | A stable partial caption was committed mid-turn (streaming ASR only). UI-only; does not drive the state machine. |
| `user_request` | `text`, `source` | A user request was finalized. `source` is `speech` (Whisper committed a turn) or `text` (`send_request(...)`). This is what drives the LLM. |
| `response_delta` | `delta` | An LLM token arrived |
| `response_done` | `text`, `reason`, `interrupted` | The response stream finished. `reason` is an `EndReason` (`completed` / `interrupted` / `error` / `empty`); `interrupted` (Bool) is kept for back-compat. |
| `playback_started` | — | First TTS sample reached the speaker |
| `playback_ended` | `reason` | Speaker stopped. `reason` is `completed` (after the audio drained) or `interrupted` (barge-in). |
| `metrics` | `loading_model`, ... | Heartbeat metrics |
| `error` | `message` | Recoverable error |

The vocabulary is deliberately invariant to *how* a request originated or
*why* playback stopped:

- `user_request` carries a `source` so a typed request (`send_request`)
  and a spoken turn flow through the **same** path to the LLM.
- Playback lifecycle (`playback_started` / `playback_ended`) is distinct
  from synthesis: `playback_ended(reason)` is what tells the UI whether the
  agent finished naturally (`completed`) or was cut off (`interrupted`),
  rather than overloading "TTS done".

For high-frequency or fan-out friendly signals, prefer the typed
channels (`llm_deltas`, `partial_transcripts`, `transcripts`,
`vad_probabilities`) over parsing `events`.

## Programmatic Controls

```swift
agent.interrupt()                     // cancel current response
agent.say("Hi there!")                // speak text, skip LLM
agent.send_request("What time is it?")// inject a text request → LLM (source: .text)
await agent.set_voice("dave")         // change TTS voice
let history = await agent.history()   // [AgentMessage]
await agent.clear_history()
await agent.update_interrupt_config(  // hot-apply on a running agent
    min_speech_ms: 200,
    mode: .speech_only
)
await agent.update_turn_config(       // .dnn endpointer only; no-op otherwise
    eot_threshold: 0.6,
    pause_trigger_ms: 256
)
await agent.stop()                    // unload models, release audio
```

`update_interrupt_config(...)` and `update_turn_config(...)` are the knobs
that can be changed on a running graph today — they forward directly to the
live `InterruptionNode` / `DNNTurnNode`. All other configuration is consumed
at `start()` and changing it requires a `stop()` + new
`TheStageVoiceAgent(config:)`.

## Latency

Measured on M-class Mac with OpenAI `gpt-4o-mini`. "First audio" is
the time between end-of-user-speech and the first sample reaching
the speaker.

| Turn | LLM 1st tok | First audio | Full speak |
|------|------------:|------------:|-----------:|
| Short reply | 487 ms | **521 ms** | 3.3 s |
| Long monologue | 575 ms | **601 ms** | **53.1 s** |
| Mid-length | 1226 ms | **1497 ms** | 5.8 s |

First-audio is dominated by LLM time-to-first-token. The on-device
pipeline (VAD + speculative Whisper + LLM-delta-streamed NeuTTS) adds
only ~100–200 ms on top of the network round-trip. LLM deltas are
plumbed straight into the TTS streaming session, so sentence
segmentation and decoder context reuse happen inside TTS — the LLM
node never has to wait for sentence boundaries.

## Background Operation (iOS)

Add `audio` to `UIBackgroundModes` in `Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

With NPU defaults (the SDK's choice), VAD / Whisper / TTS / wake word
all keep running while the app is backgrounded — the system status
bar shows the orange always-on-mic indicator. No additional lifecycle
wiring is needed in the app.


## Concurrency Note

`TheStageAI.infer` and `TheStageAI.infer_stream` are `nonisolated`,
so VAD, Whisper, NeuTTS and the LLM stream run on independent tasks
inside the agent — none of them serialize on `MainActor`. Each node
in the graph is its own actor / serial-queue-backed inference loop;
the orchestrator is just an event router and never sits on the hot
path. If you build your own orchestrator on top of these APIs, don't
wrap inference calls in `Task { @MainActor in ... }`; that re-introduces
the very serialization this design avoids.
