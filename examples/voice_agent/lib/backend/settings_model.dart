import 'package:flutter/foundation.dart';

// ============================================================================
// BACKEND layer — the config source
// ============================================================================
// `VoiceAgentSettings` holds every user-tunable knob AND knows how to flatten
// them into the `config` map that `agent.start(config:)` expects. It's the
// single place that decides WHICH models the agent uses and HOW the LLM / ASR
// / TTS are wired — so when you ask "how is the LLM connected?", the answer is
// the `llm_*` keys in [toConfig]; "how is ASR connected?" → the `stt` / `vad`
// / `turn_*` / `asr_*` keys.
//
// It's a [ChangeNotifier] so the Settings screen rebuilds live as sliders move.
// ============================================================================
class VoiceAgentSettings extends ChangeNotifier {
  // ── Voice & language ─────────────────────────────────────────────────────
  String ttsVoice = 'paul';
  String sttLanguage = 'en';
  String systemPrompt =
      'You are a helpful voice assistant. Keep responses concise.';

  // ── LLM provider (cloud only for now) ────────────────────────────────────
  // These map to the `llm_*` keys below. The agent streams the user's
  // finalized request to this endpoint and streams tokens back as
  // `response_delta` events.
  String llmProvider = 'openai_compatible';
  String llmModel = 'gpt-4o-mini';
  String llmEndpoint = 'https://api.openai.com/v1/chat/completions';
  int maxTokens = 256;
  double temperature = 0.7;

  // ── Endpointing (VAD) ────────────────────────────────────────────────────
  int silenceTimeoutMs = 600;
  double vadThreshold = 0.8;
  int vadOnsetMs = 96;
  int maxAccumulationMs = 30000;

  // ── Turn detection (end-of-turn). DNN = pipecat smart-turn on the ANE. ────
  bool useDnnTurn = true;
  double turnEotThreshold = 0.85;
  int turnEotConfirmCount = 2;
  double turnEotHighConfidence = 1.0;
  int turnPauseTriggerMs = 256;
  int turnReevalIntervalMs = 120;
  int turnMaxSilenceMs = 5000;
  int turnWindowMs = 8000;
  int turnMinSpeechMs = 250;
  // Trailing silence still fed to the streaming decoder after speech stops;
  // the smart-turn model still sees the full pause. Bounds "mm"/"?" filler.
  int turnAsrSilenceHangoverMs = 200;

  // ── Streaming ASR (live caption partials) ────────────────────────────────
  // The committed transcript is identical whether this is on or off; it only
  // controls whether `user_request_partial` captions are emitted.
  bool asrStreaming = true;
  int asrPartialIntervalMs = 600;

  // ── Diagnostics ──────────────────────────────────────────────────────────
  // Emit a single monotonic cross-node event timeline on the `Timeline`
  // os_log category. Stream on a connected Mac with:
  //   log stream --info --predicate
  //     'subsystem == "TheStageAI" AND category == "Timeline"'
  bool debugTimeline = false;

  // ── Wake word ────────────────────────────────────────────────────────────
  bool wakeWordEnabled = false;
  double wwThreshold = 0.7;
  int conversationTimeoutSec = 30;

  // ── Interruption / barge-in ──────────────────────────────────────────────
  bool allowInterruptions = true;
  String interruptMode = 'speech_only';
  int interruptMinSpeechMs = 500;
  // Sustained positive-VAD duration (ms) required to fire a barge-in. 0 =
  // derive from interruptMinSpeechMs. Pair with a high interruptThreshold to
  // reject noise / self-interrupts.
  int interruptOnsetMs = 0;
  // VAD probability threshold for barge-in, independent of the capture
  // (vadThreshold) threshold. Kept strict so the agent doesn't trip on its
  // own TTS / AEC residue while speaking.
  double interruptThreshold = 0.9;

  // Barge-in lockouts / AEC convergence. The initial lockout is a one-time,
  // longer window on the FIRST reply that covers iOS VPIO cold-start; it's set
  // generously here because on a warm restart (models cached) the first reply
  // arrives before AEC has fully converged, which otherwise self-interrupts.
  int interruptMinPlaybackMs = 250;
  int interruptInitialLockoutMs = 1500;
  int interruptThinkingLockoutMs = 600;

  // ── Audio ────────────────────────────────────────────────────────────────
  int preRollMs = 200;
  bool aecEnabled = true;
  // Silence pumped to the speaker at start so VPIO has echo reference samples
  // before the first real TTS. Bumped above the SDK default for restart margin.
  int aecWarmupMs = 400;
  int aecPlaybackGateTailMs = 80;

  // ── Debug toggles ────────────────────────────────────────────────────────
  bool showMetrics = false;
  bool showPartialTranscript = true;
  bool speculativeWhisper = true;

  static const availableVoices = ['paul', 'bril', 'dave', 'jo'];
  static const availableLanguages = ['en', 'auto', 'fr', 'de', 'es'];

  /// Flatten the settings into the `config` map `agent.start(config:)` reads.
  /// Grouped by subsystem so the LLM / ASR / TTS / turn-detection wiring is
  /// obvious at a glance.
  Map<String, dynamic> toConfig(String apiKey) => {
        // ── Models the agent loads ──
        'vad': 'TheStageAI/silero-vad',
        'stt': 'TheStageAI/thewhisper-large-v3-turbo',
        'tts': 'TheStageAI/neutts-multilingual',
        'stt_revision': 'develop',
        'tts_revision': 'develop',
        'tts_voice': ttsVoice,
        'wake_word': wakeWordEnabled ? 'TheStageAI/wake-word' : null,

        // ── LLM wiring (what produces the assistant's words) ──
        'llm_provider': llmProvider,
        'llm_model': llmModel,
        'llm_endpoint': llmEndpoint,
        'llm_api_key': apiKey,
        'system_prompt': systemPrompt,
        'max_tokens': maxTokens,
        'temperature': temperature,

        // ── VAD / endpointing ──
        'vad_threshold': vadThreshold,
        'vad_onset_ms': vadOnsetMs,
        'max_accumulation_ms': maxAccumulationMs,
        'silence_timeout_ms': silenceTimeoutMs,

        // ── Interruption / barge-in ──
        'allow_interruptions': allowInterruptions,
        'interrupt_mode': interruptMode,
        'interrupt_min_speech_ms': interruptMinSpeechMs,
        'interrupt_onset_ms': interruptOnsetMs,
        'interrupt_threshold': interruptThreshold,
        'interrupt_min_playback_ms': interruptMinPlaybackMs,
        'interrupt_initial_lockout_ms': interruptInitialLockoutMs,
        'interrupt_thinking_lockout_ms': interruptThinkingLockoutMs,

        // ── Audio / AEC ──
        'pre_roll_ms': preRollMs,
        'aec_enabled': aecEnabled,
        'aec_warmup_ms': aecWarmupMs,
        'aec_playback_gate_tail_ms': aecPlaybackGateTailMs,
        'speculative_whisper': speculativeWhisper,

        // ── Wake word ──
        'ww_threshold': wwThreshold,
        'conversation_timeout_sec': conversationTimeoutSec,

        // ── ASR language ──
        'stt_language': sttLanguage,

        // ── Turn detection (neural smart-turn on the ANE) ──
        // The `turn_detector` engines repo (TheStageAI/smart-turn-v3) is
        // injected at start() in ui/voice_chat_screen.dart and downloaded from
        // HuggingFace by the SDK. Streaming ASR runs alongside it for live
        // captions; the DNN model still owns end-of-turn.
        'turn_detection_mode': useDnnTurn ? 'dnn' : 'vad',
        'turn_detector_device': 'npu',
        'turn_eot_threshold': turnEotThreshold,
        'turn_eot_confirm_count': turnEotConfirmCount,
        'turn_eot_high_confidence': turnEotHighConfidence,
        'turn_pause_trigger_ms': turnPauseTriggerMs,
        'turn_reeval_interval_ms': turnReevalIntervalMs,
        'turn_max_silence_ms': turnMaxSilenceMs,
        'turn_window_ms': turnWindowMs,
        'turn_min_speech_ms': turnMinSpeechMs,
        'turn_asr_silence_hangover_ms': turnAsrSilenceHangoverMs,

        // ── Streaming ASR (live captions) ──
        'asr_streaming': asrStreaming,
        'asr_partial_interval_ms': asrPartialIntervalMs,

        // ── Diagnostics ──
        'debug_timeline': debugTimeline,
      };

  /// Mutate settings inside [fn] and notify listeners (the Settings screen).
  void update(void Function(VoiceAgentSettings s) fn) {
    fn(this);
    notifyListeners();
  }
}
