import 'package:flutter/foundation.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

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
  // ── Local BundledModels (ios/Runner/BundledModels via sync_local_bundles) ─
  // When true, [resolveLocalConfig] rewrites vad/stt/tts/turn + starts the
  // on-device LLM from prepare trees. When false (default), HF repo ids are
  // used and HF revisions come from the SDK ModelRevisionMap (do not pass
  // stt_revision / tts_revision / turn_detector_revision).
  bool useLocalBundles = false;

  // Bundled folder names under BundledModels/ (must match sync_local_bundles).
  String localLlmBundle = 'lfm2.5-350m';
  String localSttBundle = 'thewhisper-large-v3-turbo';
  String localTtsBundle = 'qwen3-tts-12hz-0.6b-base';
  String localVadBundle = 'silero-vad';
  String localTurnBundle = 'smart-turn-v3';

  // Handle registered with TheStageAI.start_model for bundled local LLM.
  static const localLlmHandle = 'llm';
  // Default on-device LLM when loading from HuggingFace (handle == repo id).
  static const hfLlmRepo = 'TheStageAI/LFM2.5-350M';
  static const hfSttRepo = 'TheStageAI/thewhisper-large-v3-turbo';
  static const hfTtsRepo = 'TheStageAI/Qwen3-TTS-12Hz-0.6B-Base';

  /// Shipping HF LLMs (must match ModelRevisionMap / public docs).
  static const availableHfLlms = [
    'TheStageAI/LFM2.5-350M',
    'TheStageAI/LFM2.5-230M',
    'TheStageAI/Qwen3-0.6B',
    'TheStageAI/gemma-3-1b-it',
  ];

  /// Shipping HF ASR repos.
  static const availableHfAsr = [
    'TheStageAI/thewhisper-large-v3-turbo',
    'TheStageAI/Qwen3-ASR-0.6B',
  ];

  /// Shipping HF TTS repos.
  static const availableHfTts = [
    'TheStageAI/Qwen3-TTS-12Hz-0.6B-Base',
    'TheStageAI/neutts-nano-multilingual',
  ];

  /// BundledModels folder names for local-dev mode.
  static const availableLocalLlms = [
    'lfm2.5-350m',
    'lfm2.5-230m',
    'qwen3-0.6b',
    'gemma3-1b-it',
  ];
  static const availableLocalAsr = [
    'thewhisper-large-v3-turbo',
    'qwen3-asr-0.6b',
  ];
  static const availableLocalTts = [
    'qwen3-tts-12hz-0.6b-base',
    'neutts-nano-multilingual',
  ];

  // HF repo ids used when [useLocalBundles] is false.
  String sttRepo = hfSttRepo;
  String ttsRepo = hfTtsRepo;

  // ── Voice & language ─────────────────────────────────────────────────────
  // Qwen TTS clone voice + LFM persona for the on-device Trump demo.
  String ttsVoice = 'donald_trump';
  String sttLanguage = 'en';
  // Keep this short — small LFM will parrot long style guides / phrase lists.
  // Ask for complete sentences so the model doesn't EOS after a 3-word stub.
  String systemPrompt =
      'You are Donald Trump in a short voice chat. Stay in character. '
      'Reply in 1–2 complete sentences, never a cut-off fragment.';

  // ── LLM provider ─────────────────────────────────────────────────────────
  // Local: llm_model is the start_model handle (bundled: [localLlmHandle];
  // HF: usually the repo id, e.g. [hfLlmRepo]).
  // Cloud: openai_compatible + endpoint + api key.
  String llmProvider = 'local';
  String llmModel = hfLlmRepo;
  String llmEndpoint = 'https://api.openai.com/v1/chat/completions';
  // Cloud (OpenAI-compatible) only. Local LFM uses the bundle's
  // `arch.decoder.generation` — these are not sent when llmProvider=local.
  int maxTokens = 256;
  double temperature = 0.7;

  /// Voices that make sense for the selected TTS family.
  List<String> get voicesForSelectedTts {
    final tts = useLocalBundles ? localTtsBundle : ttsRepo;
    if (tts.contains('qwen3-tts') || tts.contains('Qwen3-TTS')) {
      return const [
        'b_ref',
        'donald_trump',
        'elon_musk',
        'jensen_huang',
        'joe_biden',
      ];
    }
    // NeuTTS multilingual / nano-multilingual
    return const ['paul', 'dave', 'jo'];
  }

  void selectTtsRepo(String repo) {
    ttsRepo = repo;
    final voices = voicesForSelectedTts;
    if (!voices.contains(ttsVoice)) {
      ttsVoice = voices.first;
    }
  }

  void selectLocalTtsBundle(String bundle) {
    localTtsBundle = bundle;
    final voices = voicesForSelectedTts;
    if (!voices.contains(ttsVoice)) {
      ttsVoice = voices.first;
    }
  }

  // Sliding chat window: last N user+assistant turns. System prompt is
  // prepended every LLM call from [systemPrompt] (never trimmed with history).
  int chatMemoryMaxTurns = 10;

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
  int turnMaxSilenceMs = 2000;
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
  // iOS Voice Processing IO (hardware AEC). Off previously while debugging
  // model-load crashes; back on so the agent doesn't hear its own TTS.
  bool aecEnabled = true;
  // Silence pumped to the speaker at start so VPIO has echo reference samples
  // before the first real TTS. Bumped above the SDK default for restart margin.
  int aecWarmupMs = 400;
  int aecPlaybackGateTailMs = 80;

  // ── Debug toggles ────────────────────────────────────────────────────────
  bool showMetrics = false;
  bool showPartialTranscript = true;
  bool speculativeWhisper = true;

  static const availableVoices = [
    'b_ref',
    'donald_trump',
    'elon_musk',
    'jensen_huang',
    'joe_biden',
    'paul',
    'dave',
    'jo',
  ];
  static const availableLanguages = ['en', 'auto', 'fr', 'de', 'es'];

  /// Flatten the settings into the `config` map `agent.start(config:)` reads.
  /// Grouped by subsystem so the LLM / ASR / TTS / turn-detection wiring is
  /// obvious at a glance.
  ///
  /// Paths here are HF repo ids by default. Call [resolveLocalConfig] first
  /// when [useLocalBundles] is true so they become on-device absolute paths.
  Map<String, dynamic> toConfig(String apiKey) => {
        // ── Models the agent loads (HF by default; no revision keys —
        // ModelRevisionMap picks vA.B for this SDK build) ──
        'vad': 'TheStageAI/silero-vad',
        'stt': sttRepo,
        'tts': ttsRepo,
        'turn_detector': 'TheStageAI/smart-turn-v3',
        'tts_voice': ttsVoice,
        'wake_word': wakeWordEnabled ? 'TheStageAI/wake-word' : null,

        // ── LLM wiring (what produces the assistant's words) ──
        'llm_provider': llmProvider,
        'llm_model': useLocalBundles ? localLlmHandle : llmModel,
        'llm_endpoint': llmEndpoint,
        'llm_api_key': apiKey,
        'system_prompt': systemPrompt,
        'chat_memory_max_turns': chatMemoryMaxTurns,
        // Sampling belongs on the LLM bundle for local; only cloud needs these.
        if (llmProvider != 'local') 'max_tokens': maxTokens,
        if (llmProvider != 'local') 'temperature': temperature,
        // Local: load VAD/STT/TTS first, then LLM, then open the mic.
        if (llmProvider == 'local') 'auto_listen': false,

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

  /// Resolve BundledModels/<name> paths and patch [config] so the agent loads
  /// VAD/STT/TTS/turn from the app bundle.
  ///
  /// Does **not** start the local LLM — call [startLocalLlm] *after*
  /// `agent.start` so Whisper+Qwen TTS don't compete with LFM for RAM/ANE
  /// (TTS load was jetsamming when LFM was already resident).
  Future<Map<String, dynamic>> resolveLocalConfig(
    Map<String, dynamic> config,
  ) async {
    if (!useLocalBundles) return config;

    Future<String> pathFor(String name) async {
      final p = await TheStageFlutterSDK.get_bundled_engine_path(name);
      if (p == null || p.isEmpty) {
        throw StateError(
          'Bundled model missing: $name\n'
          'Run: test_apps/voice_agent/scripts/sync_local_bundles.sh\n'
          'then rebuild the iOS app.',
        );
      }
      return p;
    }

    final sttPath = await pathFor(localSttBundle);
    final ttsPath = await pathFor(localTtsBundle);
    final vadPath = await pathFor(localVadBundle);
    final turnPath = await pathFor(localTurnBundle);

    config['vad'] = vadPath;
    config['stt'] = sttPath;
    config['tts'] = ttsPath;
    config['turn_detector'] = turnPath;
    config['llm_provider'] = 'local';
    config['llm_model'] = localLlmHandle;
    return config;
  }

  /// Start the on-device LLM after VAD/STT/TTS are loaded.
  /// Bundled: [localLlmHandle] + BundledModels path.
  /// HF: [llmModel] as both handle and repo (revision from ModelRevisionMap).
  Future<void> startLocalLlm() async {
    if (llmProvider != 'local') return;
    final String handle;
    final String enginesPath;
    if (useLocalBundles) {
      final p = await TheStageFlutterSDK.get_bundled_engine_path(localLlmBundle);
      if (p == null || p.isEmpty) {
        throw StateError('Bundled model missing: $localLlmBundle');
      }
      handle = localLlmHandle;
      enginesPath = p;
    } else {
      handle = llmModel;
      enginesPath = llmModel;
    }
    try {
      await TheStageFlutterSDK.stop_model(model_name: handle);
    } catch (_) {}
    await TheStageFlutterSDK.start_model(
      model_name: handle,
      engines_path: enginesPath,
      model_type: 'thestage_llm',
      device: 'npu',
    );
  }

  Future<void> stopLocalLlm() async {
    if (llmProvider != 'local') return;
    final handle = useLocalBundles ? localLlmHandle : llmModel;
    try {
      await TheStageFlutterSDK.stop_model(model_name: handle);
    } catch (_) {}
  }

  /// Mutate settings inside [fn] and notify listeners (the Settings screen).
  void update(void Function(VoiceAgentSettings s) fn) {
    fn(this);
    notifyListeners();
  }
}
