# Voice Agent

End-to-end on-device voice assistant: VAD → STT → LLM → TTS, with
interruption handling, speculative transcription, and sentence-level
streaming for sub-second time-to-first-audio.

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
        case .user_speech:      print("[YOU] \(event.data["text"] ?? "")")
        case .response_delta:   print(event.data["delta"] ?? "", terminator: "")
        case .response_complete:print("\n[ASSISTANT DONE]")
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
    case 'user_speech':   print('YOU: ${event['text']}');
    case 'response_delta': stdout.write(event['delta']);
    case 'response_complete': print('\nASSISTANT DONE');
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
| `tts` | String | required | HF id or local path of NeuTTS bundle |
| `tts_voice` | String | `"paul"` | Voice preset id |
| `wake_word` | String? | `nil` | Optional wake-word bundle. When set, the agent rests in `.sleeping` until the wake word fires. |
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
| `vad_threshold` | Double | 0.5 | Speech probability threshold |
| `vad_onset_frames` | Int | 3 | Frames above threshold to trigger onset |
| `silence_timeout_frames` | Int | 19 | Frames of silence to commit turn (~600 ms) |
| `max_accumulation_seconds` | Double | 30.0 | Hard cap on a single turn |
| `pre_roll_ms` | Int | 200 | Pre-roll captured before onset |
| `speculative_whisper` | Bool | `true` | Start STT during the silence window |

When `speculative_whisper` is on (the default), Whisper is invoked on
a snapshot of the audio buffer the moment the first silent frame is
seen. By the time the silence window closes ~600 ms later, the
transcript is usually already cached — perceived STT latency drops
to **0 ms** in the steady state. The handoff is in-band: VAD pushes a
`VoiceChunk.speculate` marker on the same wire that carries voiced
frames, so STT's finalization stays in lock-step with the audio (no
cross-channel race).

### Interruption / AEC

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `interrupt_mode` | `InterruptTrigger` | `.speech_only` (iOS) / `.none` (macOS) | How (and whether) the user can barge in |
| `allow_interruptions` | Bool | computed | Back-compat alias: `true` ⇔ `interrupt_mode != .none` |
| `interrupt_min_speech_ms` | Int | 600 | Sustained speech needed to interrupt (Flutter slider goes down to 100 ms) |
| `interrupt_min_playback_ms` | Int | 250 | Grace at TTS turn start during which barge-in is suppressed (lets AEC re-converge) |
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

## Events

The legacy `events` stream stays byte-compatible. Each event is
`{ kind, data }`:

| `kind` | `data` keys | When |
|--------|-------------|------|
| `state_changed` | `state` | State transition |
| `user_speech` | `text` | Whisper has committed a turn |
| `response_delta` | `delta` | An LLM token arrived |
| `response_complete` | `text`, `interrupted` | The LLM stream finished |
| `metrics` | `loading_model`, ... | Heartbeat metrics |
| `error` | `message` | Recoverable error |

`response_complete.interrupted == true` means the user barged in before
the LLM finished — `text` is whatever was streamed up to that point.

For high-frequency or fan-out friendly signals, prefer the typed
channels (`llm_deltas`, `transcripts`, `vad_probabilities`) over
parsing `events`.

## Programmatic Controls

```swift
agent.interrupt()                     // cancel current response
agent.say("Hi there!")                // speak text, skip LLM
await agent.set_voice("dave")         // change TTS voice
let history = await agent.history()   // [AgentMessage]
await agent.clear_history()
await agent.update_interrupt_config(  // hot-apply on a running agent
    min_speech_ms: 200,
    mode: .speech_only
)
await agent.stop()                    // unload models, release audio
```

`update_interrupt_config(...)` is the only knob that can be changed on a
running graph today — it forwards directly to the live `VADNode`. All
other configuration is consumed at `start()` and changing it requires a
`stop()` + new `TheStageVoiceAgent(config:)`.

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
