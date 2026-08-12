# Voice Agent

`TheStageVoiceAgent` runs the full voice loop on device: microphone
capture, voice activity detection, end-of-turn detection, speech-to-text,
LLM (local or cloud), text-to-speech, and playback. Your app supplies
model handles and consumes typed streams; the SDK owns audio I/O and
turn-taking.

Same building blocks are available standalone — see
[VAD](./vad.md), [ASR](./asr.md), [LLM](./llm.md), [TTS](./tts.md) — and
you can mix them yourself if you don't need the orchestrator.

> **Main features**
>
> - **Full mic → speaker loop**: one entry point (`TheStageVoiceAgent` /
>   `TheStageVoiceAgentFlutter`). No manual wiring of VAD / ASR / LLM /
>   TTS handles.
> - **Turn detection you pick at build time**: Silero VAD out of the box
>   or the ANE DNN turn detector (`smart-turn-v3`) for context-aware
>   end-of-turn.
> - **Barge-in**: interrupt assistant speech (`interrupt_mode`,
>   `interrupt_min_speech_ms`) with hot-apply while running.
> - **Path A tool calling**: pass `DefaultTools.voice` / `.web` /
>   `.phone` (or your own `Tool`s) and the agent handles the tool round
>   on the same stream.
> - **Voice controls**: bundle voice id, external voice pack
>   (`tts_voice_dir`), and NeuTTS multilingual override
>   (`tts_language`); hot-swap at runtime with
>   `set_voice(voice_id:voice_dir:language:)`.
> - **Custom nodes**: VLM captions, sentiment, event logging, ports —
>   publish events on the same bus the built-in nodes use.
> - **Typed streams**: `transcripts`, `llm_deltas`,
>   `partial_transcripts`, `vad_probabilities`, and a lifecycle-tagged
>   `events` stream, all subscribable before `start()`.
> - **Flutter parity**: same config keys, same method channels, same
>   event kinds. No Dart re-implementation of the graph.

## In this page

Here we will cover the following topics:

- [**Pipeline & state machine**](#pipeline): how a turn walks from mic to speaker.
- [**API surface**](#api-surface): every Swift / Flutter entry point in one table.
- [**Quick start**](#quick-start): the smallest useful runnable app in each language.
- [**Configuration**](#configuration): `TheStageAgentConfig` fields, with hot-apply notes.
- [**Streaming**](#streaming): typed streams, event kinds, and payload shapes.
- [**Controls**](#controls): `send_request`, `say`, `interrupt`, `set_voice`, stop.
- [**Session lifecycle**](#session-lifecycle): construct → start → talk → stop, and what each phase owns.
- [**Usage Guides**](#usage-guides): barge-in, turn detection, TTS voice selection, custom nodes, tool calling, VLM as a node.
- [**Troubleshooting**](#troubleshooting): the failures we hit in real apps and how to fix them.

## Pipeline

```text
mic ─► VAD ─► ASR ─► LLM (+ tools) ─► TTS ─► speaker
                       ▲                       │
                       └────── barge-in ◄──────┘
```

Each turn walks through these states (no wake-word by default):

`idle → loading → listening → thinking → (tool_calling) → speaking → listening`

| State | UI meaning |
|-------|------------|
| `listening` | Mic open — show live caption |
| `thinking` | Waiting on LLM — spinner |
| `tool_calling` | Local tool running — chip |
| `speaking` | TTS playing — append `llm_deltas` |
| `sleeping` | Only if `wake_word` is set |

## API surface

Everything you touch on `TheStageVoiceAgent` (Swift) or
`TheStageVoiceAgentFlutter` (Flutter). All methods are `async` unless
noted; streams are subscribable before `start()`.

| Purpose | Swift | Flutter |
|---------|-------|---------|
| Build config | `TheStageAgentConfig(vad:stt:tts:llm:)` | `Map<String, Object?>` passed to `start` |
| Construct | `TheStageVoiceAgent(config:)` | `TheStageVoiceAgentFlutter()` |
| Start pipeline | `start() async throws` | `start(config:, extraNodes:)` |
| Begin listening (manual) | `begin_listening() async throws` | `beginListening()` |
| Final user text | `transcripts` | `transcripts` |
| Speakable tokens | `llm_deltas` | `llmDeltas` |
| Live captions | `partial_transcripts` | `events` → `user_request_partial` |
| VAD probability | `vad_probabilities` | `vadProbabilities` |
| Everything else | `events` | `events` |
| Push text turn | `send_request(_:)` | `sendRequest(text:)` |
| Speak only | `say(_:)` | `say(text:)` |
| Cancel playback | `interrupt()` | `interrupt()` |
| Change voice | `set_voice(voice_id:voice_dir:language:)` | `setVoice({voiceId, voiceDir, language})` |
| Chat memory | `history()` / `clear_history()` | `history()` / `clearHistory()` |
| Hot re-tune | `update_turn_config`, `update_interrupt_config` | same, `updateTurnConfig` etc. |
| Stop | `stop()` | `stop()` |

## Quick start

Smallest useful app: initialize the SDK, build a config with cloud LLM
+ on-device VAD/ASR/TTS, subscribe to streams, then `start()`. Speak into
the mic (or call `send_request`) — user text and assistant tokens arrive
on the streams you opened.

**Swift**

```swift
import TheStageSDK

try await TheStageAI.shared.initialize(apiToken: "your-api-token")

let llm = TheStageOpenAICompatibleProvider(
    endpoint: "https://api.openai.com/v1/chat/completions",
    api_key: "sk-...",
    model: "gpt-4o-mini"
)

var config = TheStageAgentConfig(
    vad: "TheStageAI/silero-vad",
    stt: "TheStageAI/thewhisper-large-v3-turbo",
    tts: "TheStageAI/neutts-nano-multilingual",
    llm: llm
)
config.system_prompt = "You are a concise voice assistant."
config.tts_voice = "paul"

let agent = TheStageVoiceAgent(config: config)

Task {
    for await text in agent.transcripts.recv() {
        print("User:", text)
    }
}
Task {
    for await token in agent.llm_deltas.recv() {
        print(token, terminator: "")
    }
}
Task {
    for await event in agent.events {
        if event.kind == .state_changed {
            print("state:", event.data["state"] ?? "?")
        }
    }
}

try await agent.start()
// talk into the mic — or agent.send_request("Hello")
// await agent.stop()
```

**Flutter**

```dart
await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

final agent = TheStageVoiceAgentFlutter();

agent.transcripts.listen((t) => print('User: $t'));
agent.llmDeltas.listen((d) => stdout.write(d));
agent.events.listen((e) {
  if (e['kind'] == 'state_changed') {
    print('state: ${(e['data'] as Map?)?['state']}');
  }
});

await agent.start(config: {
  'vad': 'TheStageAI/silero-vad',
  'stt': 'TheStageAI/thewhisper-large-v3-turbo',
  'tts': 'TheStageAI/neutts-nano-multilingual',
  'tts_voice': 'paul',
  'llm_provider': 'openai_compatible',
  'llm_endpoint': 'https://api.openai.com/v1/chat/completions',
  'llm_api_key': 'sk-...',
  'llm_model': 'gpt-4o-mini',
  'system_prompt': 'You are a concise voice assistant.',
});
```

`start()` downloads/compiles bundles on first run. Prefetch on a splash
screen (see Prefetch below).

## Models

Pass HF ids (or local paths) on the config. Omit `*_revision` → fleet pin.

| Config key | Example | Required |
|------------|---------|----------|
| `vad` | `TheStageAI/silero-vad` | yes |
| `stt` | `TheStageAI/thewhisper-large-v3-turbo` | yes |
| `tts` | `TheStageAI/neutts-nano-multilingual` or `TheStageAI/Qwen3-TTS-12Hz-0.6B-Base` | yes to speak |
| `turn_detector` | `TheStageAI/smart-turn-v3` | if `turn_end_mode == .dnn` |
| `aec_engines_path` | `TheStageAI/dtln-aec` | if `aec_method == .neural` |

**LLM**

- **Swift cloud:** `config.llm = TheStageOpenAICompatibleProvider(endpoint:api_key:model:)`
- **Swift local:** `start_model(model_name: "llm", …)` then
  `config.llm = TheStageLocalLLMProvider(model_path: "llm", tools: DefaultTools.voice)`
- **Flutter cloud:** `llm_provider: openai_compatible` + `llm_endpoint` / `llm_api_key` / `llm_model`
- **Flutter local:** `start_model` then `llm_provider: local`, `llm_model: 'llm'` (same handle),
  `llm_tools: 'voice'|'web'|'phone'|'none'`

Prefer nano NeuTTS or Qwen3-TTS. Leave `wake_word` nil (WW not in fleet).

## Configuration

Tune on `TheStageAgentConfig` **before** `start()`. Defaults already run
a full assistant.

```swift
var config = TheStageAgentConfig(
    vad: "TheStageAI/silero-vad",
    stt: "TheStageAI/thewhisper-large-v3-turbo",
    tts: "TheStageAI/neutts-nano-multilingual",
    llm: llm
)
config.tts_voice = "paul"
config.sample_rate_in = 16_000          // mic / VAD / ASR
config.sample_rate_out = 24_000         // speaker (TTS resampled here)
config.system_prompt = DefaultTools.voice_system_prompt
config.auto_listen = true

// Optional quality knobs
config.turn_end_mode = .dnn
config.turn_detector = "TheStageAI/smart-turn-v3"
config.interrupt_mode = .vad            // iOS; prefer .none on macOS
config.aec_method = .vpio               // iOS
config.asr_streaming = true             // live captions
```

| Field | Default | Notes |
|-------|---------|-------|
| `tts_voice` | `paul` | Bundle voice id (`voices/<id>/` subfolder) |
| `tts_voice_dir` | `nil` | External prepared voice pack — absolute path to a `voice.json` / `VoiceSpec` folder. Takes precedence over `tts_voice` for the initial load and for `set_voice`. |
| `tts_language` | `nil` | NeuTTS multilingual override (e.g. `"french"`). Ignored by families that key voices by id only. |
| `sample_rate_in` | `16000` | Capture rate |
| `tts_sample_rate` | `24000` | Codec native — leave alone |
| `sample_rate_out` | `24000` | Playback rate |
| `system_prompt` | voice system prompt | Re-injected each Path A turn |
| `llm_tools` | `voice` | Local Flutter/JSON preset |
| `max_tokens` | `256` | Local: overlays pack max only |
| `chat_memory_max_turns` | `10` | Flutter; Swift uses `chat_memory` / provider `memory:` |
| `auto_listen` | `true` | Else call `begin_listening()` |
| `silence_timeout_ms` | `608` | VAD end-of-turn |
| `interrupt_min_speech_ms` | `600` | Barge-in debounce |

Hot-apply while running: `update_turn_config`, `update_interrupt_config`.
Anything else → `stop()` and rebuild.

## Streaming

Subscribe **before** `start()`. Prefer typed streams for UI; use `events`
for lifecycle and tools.

| Swift | Flutter | Payload |
|-------|---------|---------|
| `transcripts` | `transcripts` | Final user utterance |
| `llm_deltas` | `llmDeltas` | Speakable assistant token |
| `partial_transcripts` | use `events` → `user_request_partial` | Live caption |
| `vad_probabilities` | `vadProbabilities` | Silero prob ~32 ms |
| `events` | `events` | `{ kind, data }` |

`events` multiplexes lifecycle and tool traffic. Each item is
`{ kind, data }`:

| Kind | `data` keys | Meaning |
|------|-------------|---------|
| `state_changed` | `state` | Lifecycle |
| `user_request_partial` | `text` | Mid-turn caption (needs `asr_streaming`) |
| `user_request` | `text`, `source` | Final user → LLM |
| `response_delta` | `delta` | Speakable token |
| `response_done` | `text`, `reason`, `interrupted` | Turn finished |
| `tool_started` / `tool_ended` | `name`, args / result | Local Path A tools |
| `playback_started` / `playback_ended` | `reason` (on end) | Speaker |
| `error` | `message` | Recoverable error |

Wire the chat UI from the typed streams (final user text + speakable
assistant tokens). Open the listeners **before** `start()` so the first
turn is not dropped. Live captions on Flutter go through `events` →
`user_request_partial` (there is no separate `partial_transcripts`
stream in Dart).

**Swift**

```swift
// Final user utterance → user bubble
Task {
    for await text in agent.transcripts.recv() {
        appendUserBubble(text)
    }
}
// Speakable assistant token → assistant bubble (while TTS plays)
Task {
    for await delta in agent.llm_deltas.recv() {
        appendAssistantDelta(delta)
    }
}
// Optional: live caption while the user is still speaking
Task {
    for await partial in agent.partial_transcripts.recv() {
        setLiveCaption(partial)
    }
}
```

**Flutter**

```dart
// Final user utterance → user bubble
agent.transcripts.listen((t) => appendUserBubble(t));
// Speakable assistant token → assistant bubble
agent.llmDeltas.listen((d) => appendAssistantDelta(d));
// Live caption (Flutter has no partial_transcripts stream)
agent.events.listen((e) {
  if (e['kind'] == 'user_request_partial') {
    final data = (e['data'] as Map?)?.cast<String, dynamic>() ?? {};
    setLiveCaption(data['text'] as String? ?? '');
  }
});
```

## Controls

Once the agent is running, drive a turn without going through the mic,
cut playback, hot-swap the TTS voice, or tear the session down:

**Swift**

```swift
agent.send_request("What time is it in Tokyo?")  // text → LLM → TTS
agent.say("Welcome back!")                       // TTS only
agent.interrupt()                                // cut playback
await agent.set_voice(voice_id: "dave")          // bundle voice
await agent.set_voice(voice_dir: "/path/to/pack")// external pack
await agent.stop()
```

**Flutter**

```dart
await agent.sendRequest('What time is it in Tokyo?');
await agent.say('Welcome back!');
await agent.interrupt();
await agent.setVoice(voiceId: 'dave');           // bundle voice
await agent.setVoice(voiceDir: '/path/to/pack');
await agent.stop();
```

## Session lifecycle

1. `initialize(apiToken:)` once per process.
2. Build config → construct agent → **subscribe** → `start()`.
3. One running agent per mic. Do not start a second without `stop()`.
4. On teardown: `await agent.stop()`. If you `start_model`'d a local LLM,
   also `stop_model` that handle.

## Usage Guides

Every recipe below is a **full runnable block** in the same style as the
Nvidia Compiler guides: build a `TheStageAgentConfig`, construct
`TheStageVoiceAgent`, subscribe to the streams you care about, then
`start()`. Fragmentary "set this flag on `config`" lines only appear
when the surrounding block from Quick Start is still on screen.

Jump to a recipe:

- [How do I run fully offline (on-device LLM)?](#how-do-i-run-fully-offline-on-device-llm)
- [How do I handle barge-in?](#how-do-i-handle-barge-in)
- [How do I show live captions / build a chat UI?](#how-do-i-show-live-captions-build-a-chat-ui)
- [What sample rates do I set (mic / TTS / speaker)?](#what-sample-rates-do-i-set-mic-tts-speaker)
- [How do I add tool calling to a voice app?](#how-do-i-add-tool-calling-to-a-voice-app)
- [How do I tune turn-taking / silence?](#how-do-i-tune-turn-taking-silence)
- [How do I pick a TTS voice in the agent?](#how-do-i-pick-a-tts-voice-in-the-agent)
- [How do I add a custom node (e.g. VLM captions)?](#how-do-i-add-a-custom-node-e-g-vlm-captions)
- [How do I offload models for a heavy node (ephemeral roster)?](#how-do-i-offload-models-for-a-heavy-node-ephemeral-roster)
- [How do I keep the agent alive in iOS background?](#how-do-i-keep-the-agent-alive-in-ios-background)

### How do I run fully offline (on-device LLM)?

You want the microphone → answer → speaker loop to work with no network.
The three audio bundles (VAD, ASR, TTS) already run on device; the
one moving piece is the LLM. `TheStageLocalLLMProvider` reuses a model
handle you load through the SDK singleton, so the agent never touches
the network at inference time.

Loading is a two-step dance: first `start_model` a local LLM under a
handle name of your choice, then hand the same handle to
`TheStageLocalLLMProvider` (Swift) or `llm_provider: 'local'` +
`llm_model: '<same handle>'` (Flutter).

**Swift:**

```swift
import TheStageSDK

try await TheStageAI.shared.initialize(apiToken: "your-api-token")

try await TheStageAI.shared.start_model(
    model_name: "llm",
    engines_path: "TheStageAI/Qwen3-0.6B"
)

let llm = TheStageLocalLLMProvider(
    model_path: "llm",                          // must equal start_model handle
    tools: DefaultTools.voice,                  // Path A tools; pass [] to disable
    system_prompt: DefaultTools.voice_system_prompt,
    memory: .SLIDING(max_turns: 10)
)

var config = TheStageAgentConfig(
    vad: "TheStageAI/silero-vad",
    stt: "TheStageAI/thewhisper-large-v3-turbo",
    tts: "TheStageAI/neutts-nano-multilingual",
    llm: llm
)
config.system_prompt = DefaultTools.voice_system_prompt
config.llm_tools = "voice"
config.auto_listen = false                      // start muted; opt-in below

let agent = TheStageVoiceAgent(config: config)
try await agent.start()
try await agent.begin_listening()               // open the mic
```

**Flutter:**

```dart
await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

await TheStageFlutterSDK.start_model(
  model_name: 'llm',
  engines_path: 'TheStageAI/Qwen3-0.6B',
  model_type: 'thestage_llm',
);

final agent = TheStageVoiceAgentFlutter();
await agent.start(config: {
  'vad': 'TheStageAI/silero-vad',
  'stt': 'TheStageAI/thewhisper-large-v3-turbo',
  'tts': 'TheStageAI/neutts-nano-multilingual',
  'tts_voice': 'dave',
  'llm_provider': 'local',
  'llm_model': 'llm',                           // must equal start_model handle
  'llm_tools': 'voice',                         // none | voice | web | phone
  'chat_memory_max_turns': 10,
  'auto_listen': false,
});
await agent.beginListening();
```

You can reuse the HF repo id as the handle name — keep the two strings
identical to avoid confusion. Local Path A overlays only `max_tokens`
onto the pack's `generation_defaults`; do not push a cloud
`temperature` through to a local LFM.

### How do I handle barge-in?

You want the assistant to stop mid-sentence the moment the user starts
speaking again, and then answer the new question. This is barge-in.

Barge-in has two configuration surfaces: **build-time** knobs on
`TheStageAgentConfig` (which mode, initial thresholds) and **hot-apply**
knobs on the live agent (`update_interrupt_config`). Build a config
with the mode you want, subscribe to `events` so you can react to
playback interruption in the UI, then start:

```swift
import TheStageSDK

try await TheStageAI.shared.initialize(apiToken: "your-api-token")

let llm = TheStageOpenAICompatibleProvider(
    endpoint: "https://api.openai.com/v1/chat/completions",
    api_key: "sk-...",
    model: "gpt-4o-mini"
)

var config = TheStageAgentConfig(
    vad: "TheStageAI/silero-vad",
    stt: "TheStageAI/thewhisper-large-v3-turbo",
    tts: "TheStageAI/neutts-nano-multilingual",
    llm: llm
)
config.interrupt_mode = .vad                    // iOS default; use .none on macOS
config.interrupt_min_speech_ms = 600            // ignore anything shorter than 600 ms
config.aec_method = .vpio                       // iOS AEC; .none on macOS w/o headphones

let agent = TheStageVoiceAgent(config: config)

Task {
    for await event in agent.events {
        switch event.kind {
        case .playback_ended:
            let reason = event.data["reason"] as? String ?? ""
            if reason == "interrupted" { print("barge-in cut TTS") }
        case .user_request:
            print("new turn after barge-in:", event.data["text"] ?? "")
        default: break
        }
    }
}

try await agent.start()
```

While the agent is running you can tighten or relax barge-in without
tearing down the graph. `update_interrupt_config` forwards straight to
the live `InterruptionNode`:

```swift
await agent.update_interrupt_config(
    min_speech_ms: 200,                          // snappier — more false triggers
    mode: .vad                                   // .none disables barge-in
)
```

Tuning bullets, tied to the fields above:

- Lower `interrupt_min_speech_ms` → snappier, more false triggers.
- On **macOS**, keep `interrupt_mode = .none` or wear headphones; there
  is no hardware AEC.
- On **iOS**, keep `aec_method` at `.vpio` (or `.neural` with a DTLN
  bundle) — the mic will otherwise hear the speaker and self-cancel.

### How do I show live captions / build a chat UI?

You want three UI streams: a live growing caption while the user is
speaking, a settled user bubble at end of turn, and a streaming
assistant bubble that grows as the LLM emits tokens. All three come off
`TheStageVoiceAgent` as typed streams — subscribe **before** `start()`
so the first turn never gets lost.

```swift
import TheStageSDK

try await TheStageAI.shared.initialize(apiToken: "your-api-token")

let llm = TheStageOpenAICompatibleProvider(
    endpoint: "https://api.openai.com/v1/chat/completions",
    api_key: "sk-...",
    model: "gpt-4o-mini"
)
var config = TheStageAgentConfig(
    vad: "TheStageAI/silero-vad",
    stt: "TheStageAI/thewhisper-large-v3-turbo",
    tts: "TheStageAI/neutts-nano-multilingual",
    llm: llm
)
config.asr_streaming = true                     // needed for partial_transcripts

let agent = TheStageVoiceAgent(config: config)

Task {
    for await partial in agent.partial_transcripts.recv() {
        listeningLabel.text = partial            // grows while the user talks
    }
}
Task {
    for await transcript in agent.transcripts.recv() {
        chatHistory.append(UserMessage(text: transcript))
    }
}
Task {
    for await delta in agent.llm_deltas.recv() {
        assistantBubble.text += delta            // grows as the LLM emits tokens
    }
}
Task {
    for await p in agent.vad_probabilities.recv() {
        micMeter.level = p                       // 0…1 mic level meter
    }
}

try await agent.start()
```

Flutter uses `Stream.listen`. Live captions are not on a dedicated
Flutter stream — they arrive as `events` with `kind:
user_request_partial`:

```dart
final agent = TheStageVoiceAgentFlutter();

agent.transcripts.listen((text) {
  setState(() => chatHistory.add(UserMessage(text)));
});
agent.llmDeltas.listen((delta) {
  setState(() => assistantText += delta);
});
agent.vadProbabilities.listen((p) {
  setState(() => micLevel = p);
});
agent.events.listen((e) {
  if (e['kind'] == 'user_request_partial') {
    final data = (e['data'] as Map?)?.cast<String, dynamic>() ?? {};
    setState(() => caption = data['text'] as String? ?? '');
  }
});

await agent.start(config: {
  'vad': 'TheStageAI/silero-vad',
  'stt': 'TheStageAI/thewhisper-large-v3-turbo',
  'tts': 'TheStageAI/neutts-nano-multilingual',
  'asr_streaming': true,                        // required for live captions
  'llm_provider': 'openai_compatible',
  'llm_endpoint': 'https://api.openai.com/v1/chat/completions',
  'llm_api_key': 'sk-...',
  'llm_model': 'gpt-4o-mini',
});
```

There is no standalone Flutter ASR streamer today; the Voice Agent is
the product path for live captions (see also [asr.md](./asr.md)).

### What sample rates do I set (mic / TTS / speaker)?

The agent has three rate knobs, one per stage of the audio path. The
mic side is fixed by VAD / Whisper. The codec side is fixed by NeuTTS /
Qwen3-TTS. The speaker side is **your** setting — match it to whatever
your `AVAudioSession` output is, and the agent will resample the 24 kHz
TTS codec output to that rate before playback.

| Knob | Default | Role |
|------|---------|------|
| `sample_rate_in` | `16000` | Mic capture → VAD → Whisper |
| `tts_sample_rate` | `24000` | Codec native rate (NeuCodec / Qwen3) |
| `sample_rate_out` | `24000` | Speaker rate; the agent resamples TTS here |

```swift
import TheStageSDK

try await TheStageAI.shared.initialize(apiToken: "your-api-token")

var config = TheStageAgentConfig(
    vad: "TheStageAI/silero-vad",
    stt: "TheStageAI/thewhisper-large-v3-turbo",
    tts: "TheStageAI/neutts-nano-multilingual",
    llm: llm
)
config.sample_rate_in  = 16_000                 // do not change
config.tts_sample_rate = 24_000                 // do not change
config.sample_rate_out = 48_000                 // match your AVAudioSession

let agent = TheStageVoiceAgent(config: config)
try await agent.start()
```

If playback sounds chipmunk / sluggish, `sample_rate_out` is wrong.
Standalone TTS (outside the agent) has its own `sample_rate_out` on
`TTSGenerationConfig` — that one resamples in the pipeline, not at the
audio engine (see [tts.md](./tts.md)).

### How do I add tool calling to a voice app?

You want the assistant to call local tools (weather, timers, calendar,
phone actions) during a voice turn, then keep speaking with the tool
result folded in. This is **Path A** — the local LLM provider owns a
`TheStageChatSession`, runs `Tool.execute`, emits `tool_started` /
`tool_ended`, and only speakable `text_delta` chunks reach the TTS.

Who owns what:

| Layer | Owns |
|-------|------|
| Voice Agent | Mic → VAD → ASR → local Path A turn → TTS, barge-in, captions |
| `TheStageChatSession` | Sliding memory, tool rounds, KV trim |
| `DefaultTools.*` | Built-in `execute` handlers (`voice`, `web`, `phone`) |

Pass the tool set on the provider — the agent picks up tools from
whatever the provider was constructed with. `config.llm_tools` is
metadata / Flutter parity; the source of truth in Swift is the provider:

```swift
import TheStageSDK

try await TheStageAI.shared.initialize(apiToken: "your-api-token")
try await TheStageAI.shared.start_model(
    model_name: "llm",
    engines_path: "TheStageAI/Qwen3-0.6B"
)

let llm = TheStageLocalLLMProvider(
    model_path: "llm",
    tools: DefaultTools.voice,                  // or .web / .phone / []
    system_prompt: DefaultTools.voice_system_prompt,
    memory: .SLIDING(max_turns: 10)
)

var config = TheStageAgentConfig(
    vad: "TheStageAI/silero-vad",
    stt: "TheStageAI/thewhisper-large-v3-turbo",
    tts: "TheStageAI/neutts-nano-multilingual",
    llm: llm
)
config.system_prompt = DefaultTools.voice_system_prompt
config.llm_tools = "voice"                      // label / Flutter parity

let agent = TheStageVoiceAgent(config: config)

Task {
    for await event in agent.events {
        switch event.kind {
        case .tool_started: print("tool:", event.data["name"] ?? "?")
        case .tool_ended:   print("tool result received")
        case .response_delta:
            let d = event.data["delta"] as? String ?? ""
            print(d, terminator: "")             // speakable text
        default: break
        }
    }
}

try await agent.start()
```

**Flutter (same idea):**

```dart
await TheStageFlutterSDK.start_model(
  model_name: 'llm',
  engines_path: 'TheStageAI/Qwen3-0.6B',
  model_type: 'thestage_llm',
);

final agent = TheStageVoiceAgentFlutter();
await agent.start(config: {
  'vad': 'TheStageAI/silero-vad',
  'stt': 'TheStageAI/thewhisper-large-v3-turbo',
  'tts': 'TheStageAI/neutts-nano-multilingual',
  'llm_provider': 'local',
  'llm_model': 'llm',
  'llm_tools': 'voice',                         // none | voice | web | phone
  'chat_memory_max_turns': 10,
});
```

A single voice turn with tools then looks like:

```text
[Voice Agent]              [TheStageLocalLLMProvider → ChatSession]
 mic → ASR → user text ──► submit_stream (Path A)
                              text_delta  "Okay, let me check…"  → TTS
                              tool_call   → Tool.execute          (silent)
                              tool_started / tool_ended            (UI)
                              text_delta  "It's 18°C in Paris."  → TTS
```

Only speak `text_delta` / `response_delta`. Never speak `tool_call`
payloads or `tool_result` bodies.

**Phone tools open system UI.** Actions like `compose_email` /
`compose_sms` / `dial_phone` / `open_maps` do not send mail or place a
call by themselves — they open the corresponding system UI with fields
prefilled. `voice_system_prompt` already explains that. A typical
`compose_email` turn:

1. User: "Email Alice that I'm running late."
2. TTS: "Sure, opening a draft…" (`text_delta` filler)
3. Mail app opens with `mailto:` prefilled (`compose_email`).
4. TTS: "I've opened a draft to Alice — tap Send when you're ready."

For non-catalog tools or cloud tool APIs, build a custom provider /
graph and yield only speakable deltas — see
[LLM tools](./llm.md#how-do-i-pass-tools-and-read-tool-calls) and the
`voice_agent_custom_nodes` example. Cloud OpenAI-compatible providers
inside the agent do not produce TheStage `ToolCall` events.

### How do I tune turn-taking / silence?

Turn detection controls when "the user has finished speaking" fires,
triggering the LLM call. Two modes:

- **VAD (default)** — commit after `silence_timeout_ms` of silence
  following speech. Simple, cheap, cuts off mid-sentence pauses.
- **DNN (`smart-turn-v3`)** — a neural end-of-turn detector, tolerates
  mid-sentence pauses, at the cost of loading one extra small bundle.

Pick the mode at build time. The DNN mode needs `turn_detector` set to
a supported bundle; VAD only needs `silence_timeout_ms`:

```swift
var config = TheStageAgentConfig(
    vad: "TheStageAI/silero-vad",
    stt: "TheStageAI/thewhisper-large-v3-turbo",
    tts: "TheStageAI/neutts-nano-multilingual",
    llm: llm
)
config.turn_end_mode = .dnn
config.turn_detector = "TheStageAI/smart-turn-v3"
config.turn_eot_threshold = 0.6                 // lower → commit sooner
config.silence_timeout_ms = 608                 // VAD fallback, still respected
```

Once the agent is running, DNN knobs hot-apply — no restart needed:

```swift
await agent.update_turn_config(
    eot_threshold: 0.7,
    pause_trigger_ms: 256
)
```

Rules of thumb:

- Cuts off mid-sentence → switch to `.dnn` + `smart-turn-v3`, or raise
  `silence_timeout_ms` on `.vad`.
- Responds too slowly → lower `turn_eot_threshold` (DNN) or
  `silence_timeout_ms` (VAD).
- Leave `turn_eot_high_confidence` at `1.0` unless you can verify that
  final transcripts are not being truncated.

### How do I pick a TTS voice in the agent?

There are three ways to pin a voice on the agent, and they compose:

1. **Bundle voice by id** — pick a speaker that ships inside the TTS
   pack (`voices/<id>/`). NeuTTS ships `paul`, `dave`, `jo`; Qwen3-TTS
   ships `b_ref`.
2. **External prepared pack (`voice_dir`)** — point the agent at a
   folder you produced with the standalone TTS voice-prep tools
   (`voice.json` / `VoiceSpec`). Same folder shape you'd hand to
   `Qwen3TTSPipeline(..., voice_dir:)` or `NeuTTS.set_voice(voice_dir:)`.
3. **Language override** — NeuTTS multilingual selects the same speaker
   in a different language (e.g. `paul` in French).

Everything below runs on the exact same `TheStageAgentConfig` you
already build for `start()` — no new pipelines, no separate loader.

**Initial load (config-time)**

Set the voice on the config before you construct the agent. Only
`tts_voice_dir` needs an absolute path; `tts_voice` and `tts_language`
are plain strings.

```swift
var config = TheStageAgentConfig(
    vad: "TheStageAI/silero-vad",
    stt: "TheStageAI/thewhisper-large-v3-turbo",
    tts: "TheStageAI/neutts-nano-multilingual",
    llm: llm
)

// (a) bundle voice
config.tts_voice = "dave"

// (b) external prepared pack — takes precedence over `tts_voice`
config.tts_voice_dir = "/Library/Application Support/MyApp/voices/tutor_dave"

// (c) NeuTTS multilingual: same speaker, different language
config.tts_language = "french"

let agent = TheStageVoiceAgent(config: config)
try await agent.start()
```

Under the hood the agent forwards these three fields into the singleton
`start_model("tts", …, config: [...])` call — the same dict shape the
standalone `TTSPipeline` accepts. Auto-routing (NeuTTS vs Qwen3) still
picks the family from the TTS bundle layout.

**Runtime hot-swap**

`set_voice(...)` on the running agent accepts any subset of the three
fields and mirrors the standalone `TTSPipeline.set_voice(voice_dir:
voice_id: language:)` signature. `nil` fields are left untouched on the
agent config, so a later `stop()` / `start()` cycle still uses the
swap:

```swift
// From a UI button — bundle voice.
await agent.set_voice(voice_id: "paul")

// Point the running agent at a prepared pack the user just downloaded.
await agent.set_voice(voice_dir: prepared_pack_url.path)

// Combine — bundle speaker + language override on NeuTTS multilingual.
await agent.set_voice(voice_id: "paul", language: "french")

// Clear an external pack and fall back to the bundle id — pass `""`.
await agent.set_voice(voice_dir: "")
```

The legacy positional form `agent.set_voice("paul")` still compiles
and is equivalent to `set_voice(voice_id: "paul")`.

**Flutter**

Both fields are plain start-config keys, and `setVoice` accepts the
same named args:

```dart
await agent.start(config: {
  'tts': 'TheStageAI/Qwen3-TTS-12Hz-0.6B-Base',
  'tts_voice': 'b_ref',                          // bundle id
  'tts_voice_dir': '/path/to/prepared_pack',     // external pack (optional)
  'tts_language': 'french',                      // multilingual override (optional)
  // …vad / stt / llm …
});

// Runtime hot-swap — same shape as Swift.
await agent.setVoice(voiceDir: '/path/to/prepared_pack');
await agent.setVoice(voiceId: 'paul', language: 'french');
```

**Producing a `voice_dir`**

The voice pack itself is produced by the standalone TTS voice-prep
tools (see [tts.md](./tts.md#voice-controls) → "How do I change voice /
language / clone a speaker?"). The agent just consumes the finished
folder — the same one you would pass to
`Qwen3TTSPipeline(voice_dir:...)` or `NeuTTS.set_voice(voice_dir:...)`.

**Cost of a hot-swap**

`agent.set_voice(...)` today stops and restarts the TTS engine — same
cost as any TTS reload (fast, but not free). It's the price of running
inside the agent's `start_model("tts")` scope. If you need the cheaper
pipeline-level `set_voice` (no engine reload), drop out of the agent
and use the standalone TTS pipeline directly.

### How do I add a custom node (e.g. VLM captions)?

The SDK ships the base type only (`TheStageAgentNode` /
`AgentNodeContext`) — **you keep the node instances**; the agent does
not hand them back. Copy the wiring from the SDK examples
(`examples/voice_agent_custom_nodes` → `lib/nodes/`).

| Step | What you do |
|------|-------------|
| 1. Construct | `final vlm = VLMCaptionNode(...); final log = EventLogNode(...);` |
| 2. Attach | Pass the instances into `agent.start(extraNodes: […])` |
| 3. Call in | Call methods on **your** handle (`vlm.submitImage(...)`) |
| 4. Read out | The node's own Dart `Stream`, and/or `agent.portEvents`, and/or `onEvent` |

**Flutter — construct handles, subscribe, then start:**

```dart
final agent = TheStageVoiceAgentFlutter();

final eventLog = EventLogNode(
  onBusEvent: (e) {
    // Internal bus: STATE | USER_REQUEST | BARGE_IN | TOOL_STARTED | …
    debugPrint('${e['kind']}: $e');
  },
);
final vlm = VLMCaptionNode(
  id: 'vlm',
  enginesPath: 'TheStageAI/LFM2.5-VL-450M',
  runWhen: const ['idle', 'sleeping', 'listening'], // quiet states only
  lifecycle: VlmLifecycle.external,                 // host ModelRoster owns start/stop
);

// Subscribe BEFORE start — ports and captions can fire the moment the node attaches.
vlm.captions.listen((text) => setState(() => lastCaption = text));

agent.portEvents.listen((e) {
  // Built-ins: vad.probability, llm.delta, transcripts.final, …
  // Custom node ports are "$nodeId.$localName" — here "vlm.caption".
  if (e['port'] == 'vlm.caption') {
    setState(() => lastCaption = e['value']?.toString() ?? '');
  }
});

await agent.start(
  config: {
    'vad': 'TheStageAI/silero-vad',
    'stt': 'TheStageAI/thewhisper-large-v3-turbo',
    'tts': 'TheStageAI/Qwen3-TTS-12Hz-0.6B-Base',
    'llm_provider': 'local',
    'llm_model': 'llm',
  },
  extraNodes: [vlm, eventLog],
);
await agent.beginListening();

// Drive the node from UI / camera later — same instance you held above.
await vlm.submitImage(path: pickedImagePath);
```

Inside the node, `ctx.sendPort('caption', text)` becomes bus port
**`vlm.caption`** (`$nodeId.$name`). Prefer the node's own
`vlm.captions` stream inside your widget; use `agent.portEvents` when a
widget shouldn't import the node class directly.

Minimal bus listener node (same pattern as the demo):

```dart
class EventLogNode extends TheStageAgentNode {
  EventLogNode({this.id = 'event_log', this.onBusEvent});
  @override final String id;
  @override final List<String> runWhen = const [];
  final void Function(Map<String, dynamic>)? onBusEvent;

  @override
  Future<void> onEvent(AgentNodeContext ctx, Map<String, dynamic> e) async {
    onBusEvent?.call(e);
  }
}
```

**Swift — same shape:**

```swift
final class EventLogNode: TheStageAgentNode {
    override var run_when: Set<TheStageAgentState> { [] }

    override func on_start() async throws {
        guard let stream = subscribe() else { return }
        Task {
            for await event in stream {
                print("bus:", event)              // USER_REQUEST, STATE, …
            }
        }
    }
}

let log = EventLogNode(id: "event_log")
var config = TheStageAgentConfig(
    vad: "TheStageAI/silero-vad",
    stt: "TheStageAI/thewhisper-large-v3-turbo",
    tts: "TheStageAI/neutts-nano-multilingual",
    llm: TheStageLocalLLMProvider(model_path: "llm")
)
config.extra_nodes = [log]

let agent = TheStageVoiceAgent(config: config)
try await agent.start()

// Built-in typed ports (no custom node required):
Task {
    for await p in agent.ports
        .channel("vad.probability", as: Double.self).recv()
    {
        micMeter = p
    }
}
```

Full VLM + `ModelRoster` wiring is in
`examples/voice_agent_custom_nodes` (`DemoController.start` /
`captionImage`).

### How do I offload models for a heavy node (ephemeral roster)?

Adding a VLM on top of ASR + LLM + TTS often OOMs or fights for ANE.
Use a host-side `ModelRoster` (from the same demo): mark slots as
`resident` / `warmDisk` / `ephemeral`, then wrap the burst in
`withEphemeralSwap`. Compiled engines stay on disk — next start is
cheap.

You call methods on the **same** `vlm` you passed to `extraNodes`:

```dart
Future<void> captionWhenQuiet(String imagePath) async {
  // Wait until agent state is idle | sleeping | listening.
  await roster.withEphemeralSwap(
    'vlm',
    park: const ['llm', 'stt', 'tts'],
    body: () async {
      vlm.markReady(ready: true);              // lifecycle: external
      await vlm.submitImage(path: imagePath);
    },
  );
  vlm.markReady(ready: false);
}
```

`withEphemeralSwap` starts the VLM, parks the heavy residents, runs the
body, then stops the VLM and restores the parked models.

### How do I keep the agent alive in iOS background?

Add `audio` to `UIBackgroundModes` in `Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

With NPU defaults, VAD / Whisper / TTS keep running while the app is
backgrounded — the system status bar shows the orange always-on-mic
indicator. No extra lifecycle wiring in the app.

## Troubleshooting

### Agent interrupts itself (echo barge-in)

Own TTS is heard as user speech — missing / weak AEC.

1. **macOS:** `interrupt_mode = .none` (default) or headphones.
2. **iOS:** `aec_method` = `vpio` or `neural` (not `none`).
3. Raise `interrupt_min_speech_ms` (e.g. 800) if still too twitchy.

### Cuts off the user / responds too slowly

Turn-taking timing — see [tune turn-taking](#how-do-i-tune-turn-taking--silence).
Prefer `.dnn` + `smart-turn-v3` for mid-sentence pauses; adjust
`silence_timeout_ms` on `.vad`.

### No mic / permission / silence forever

Confirm mic permission, audio session category, and
`sample_rate_in == 16000`. On iOS background, require `UIBackgroundModes`
audio. Check `state_changed` reaches `listening`.

### Playback too fast / slow

Set `sample_rate_out` to the real speaker rate. TTS codec stays 24 kHz;
the agent resamples. Standalone TTS mistakes do not apply the same fix —
see [tts.md](./tts.md).

### Offline LLM never answers / wrong model

`llm_model` / `model_path` must equal the `start_model` handle. Local
provider ignores agent `temperature` / `max_tokens`. Confirm
`start_model` completed before `agent.start()`.

### OOM when adding VLM / heavy node

Offload session models around the burst (`release` → `withEphemeral` →
`ensureHot`). Gate with `runWhen` on quiet states only.

### Custom node never fires

Subscribe after bind; use **internal** UPPERCASE bus kinds in
`onEvent`, not public `state_changed`. Set `runWhen` to states that
actually occur. Confirm `extraNodes` / `extra_nodes` passed into
`start`.

### Cold start takes tens of seconds

First `agent.start()` downloads + compiles every bundle. Prefetch on a
splash screen (below).

### Barge-in too aggressive / never triggers

Tune `interrupt_min_speech_ms`, `interrupt_threshold`, and lockout
fields (`interrupt_min_playback_ms`, `interrupt_initial_lockout_ms`).
macOS without AEC cannot safely use speech barge-in.

## Load Progress / Prefetch / Cleanup

### Prefetch

Move downloads off the critical path before `agent.start()`:

```swift
import TheStageSDK

let ai = TheStageAI.shared
try await ai.initialize(apiToken: "your-api-token")

_ = try await ai.prefetch_engines(repo_id: "TheStageAI/silero-vad")
_ = try await ai.prefetch_engines(
    repo_id: "TheStageAI/thewhisper-large-v3-turbo"
)
_ = try await ai.prefetch_engines(
    repo_id: "TheStageAI/neutts-nano-multilingual"
)
// optional: smart-turn-v3, local LLM, Qwen3-TTS, …
```

Progress callbacks match other pipelines — see
[Load Progress](./README.md#load-progress). Flutter:
`TheStageFlutterSDK.on_progress` + `prefetch` / `start_model` for the
local LLM handle.

### Cleanup

```swift
await agent.stop()   // unload graph models, release audio
```

```dart
await agent.stop();
```

If you `start_model`'d a local LLM outside the agent, also
`stop_model` that handle when tearing down the session. Ephemeral
roster slots should leave quiet states with `ensureHot` restored for
the next turn.
