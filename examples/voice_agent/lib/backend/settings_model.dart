import 'package:flutter/foundation.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

/// Official vendor sampling for the selected LLM. LFM ≠ Qwen ≠ Gemma.
class LlmSamplingCard {
  const LlmSamplingCard({
    required this.name,
    required this.temperature,
    required this.topK,
    required this.topP,
    required this.minP,
    required this.repetitionPenalty,
  });

  final String name;
  final double temperature;
  final int topK;
  final double topP;
  final double minP;
  final double repetitionPenalty;

  /// LiquidAI LFM2.5.
  static const lfm = LlmSamplingCard(
    name: 'LFM2.5',
    temperature: 0.1,
    topK: 50,
    topP: 1.0,
    minP: 0.15,
    repetitionPenalty: 1.05,
  );

  /// Qwen3 non-thinking (voice loop has thinking off).
  static const qwen3NonThinking = LlmSamplingCard(
    name: 'Qwen3 non-thinking',
    temperature: 0.7,
    topK: 20,
    topP: 0.8,
    minP: 0.0,
    repetitionPenalty: 1.0,
  );

  /// Gemma 3 instruct.
  static const gemma3 = LlmSamplingCard(
    name: 'Gemma 3',
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    minP: 0.0,
    repetitionPenalty: 1.0,
  );

  static LlmSamplingCard forModel(String id) {
    final n = id.toLowerCase();
    if (n.contains('qwen')) return qwen3NonThinking;
    if (n.contains('gemma')) return gemma3;
    return lfm;
  }

  String get summary =>
      '$name  temp $temperature / top_k $topK / top_p $topP / '
      'min_p $minP / rep $repetitionPenalty';
}

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
  // ── Local BundledModels (optional ios/Runner/BundledModels offline stack) ─
  // When true, [resolveLocalConfig] rewrites vad/stt/tts/turn + starts the
  // on-device LLM from prepare trees. When false (default), HF repo ids are
  // used and HF revisions come from the SDK ModelRevisionMap (do not pass
  // stt_revision / tts_revision / turn_detector_revision).
  bool useLocalBundles = false;

  // Bundled folder names under BundledModels/ (optional offline stack).
  String localLlmBundle = 'lfm2.5-350m';
  String localSttBundle = 'thewhisper-large-v3-turbo';
  String localTtsBundle = 'neutts-nano-multilingual';
  String localVadBundle = 'silero-vad';
  String localTurnBundle = 'smart-turn-v3';

  // Handle registered with TheStageAI.start_model for bundled local LLM.
  static const localLlmHandle = 'llm';
  // Default on-device LLM when loading from HuggingFace (handle == repo id).
  static const hfLlmRepo = 'TheStageAI/LFM2.5-350M';
  static const hfSttRepo = 'TheStageAI/thewhisper-large-v3-turbo';
  static const hfTtsRepo = 'TheStageAI/neutts-nano-multilingual';

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
    'TheStageAI/parakeet-tdt-0.6b-v3',
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
    'parakeet-tdt-0.6b-v3',
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
  String ttsVoice = 'paul';
  String sttLanguage = 'en';
  // Short strict persona. No few-shot cities — small packs copy them.
  // Wire format (Qwen XML / LFM python / Gemma tool_code) comes from the
  // SDK tools section, not here. Keep "Tool pattern (always):" so the SDK
  // does not append a second spoken-hint block.
  String systemPrompt = '''
You are a short on-device voice assistant. Answer in complete sentences. Use the user's language.

        Tools are only for live facts the user asked for (weather, time, search). Greetings, chit-chat, and opinions: answer yourself — no tool, no filler, no city, no weather.

Tool pattern (always):
1) Need a tool? One short filler, then the exact markup from the tools section (do not speak the markup).
2) After the tool result: 1–2 sentences using only that result.
3) No tool needed? Answer the question directly.

Never invent facts. Never name a place, time, or number the user did not ask and the tool did not return. Never read JSON aloud. Never stop after one word.
'''.trim();

  /// Built-in tool preset for local LLM: none | voice | web | phone | live.
  /// Default `web` is the 3 live-fact tools (weather, time, search).
  String llmTools = 'web';

  // ── LLM provider ─────────────────────────────────────────────────────────
  // Local: llm_model is the start_model handle (bundled: [localLlmHandle];
  // HF: usually the repo id, e.g. [hfLlmRepo]).
  // Cloud: openai_compatible + endpoint + api key.
  String llmProvider = 'local';
  String llmModel = hfLlmRepo;
  String llmEndpoint = 'https://api.openai.com/v1/chat/completions';
  // Cloud (OpenAI-compatible) HTTP body. Local Path A overlays that
  // model's vendor card (see [LlmSamplingCard.forModel]).
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

  // Sliding chat window: last N complete USER-led turns. System prompt is
  // re-injected every LLM call from [systemPrompt] (not stored in history).
  // The SDK also token-trims to the pack's max_cache_len (LFM2.5-350M ≈ 1256)
  // via LLMChatEngine.fit_messages, so we do NOT need a tight app cap here —
  // fit_messages drops oldest USER-led turns just enough to keep room for a
  // filler + tool call + short answer. Setting a low N here only throws away
  // memory that would otherwise fit.
  int chatMemoryMaxTurns = 10;

  // ── Endpointing (VAD) ────────────────────────────────────────────────────
  int silenceTimeoutMs = 608; // SDK default
  double vadThreshold = 0.7; // SDK default (negative 0.15), same as the ASR test app
  int vadOnsetMs = 256; // SDK default: 2 hits inside this window
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
  //
  // `null` — the default — lets the SDK derive it from the loaded model's
  // streaming policy, where the value is actually tuned. It was hardcoded
  // 200 here and sent on every start, so the tuned value could never reach
  // the agent no matter what the SDK shipped. Set it to override.
  int? turnAsrSilenceHangoverMs;

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
  int interruptMinSpeechMs = 600; // SDK default
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
  int preRollMs = 300; // SDK default
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
    'paul',
    'dave',
    'jo',
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

  String get selectedLlmId => useLocalBundles ? localLlmBundle : llmModel;

  LlmSamplingCard get samplingCard =>
      LlmSamplingCard.forModel(selectedLlmId);

  /// Flatten the settings into the `config` map `agent.start(config:)` reads.
  /// Grouped by subsystem so the LLM / ASR / TTS / turn-detection wiring is
  /// obvious at a glance.
  ///
  /// Paths here are HF repo ids by default. Call [resolveLocalConfig] first
  /// when [useLocalBundles] is true so they become on-device absolute paths.
  Map<String, dynamic> toConfig(String apiKey) {
    return {
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
        'llm_tools': llmTools,
        'chat_memory_max_turns': chatMemoryMaxTurns,
        'max_tokens': maxTokens,
        'temperature': temperature,
        // Per-model vendor card (LFM ≠ Qwen ≠ Gemma). Tools: weather/time/search.
        // Sampling comes from the pack: each bundle's decoder spec carries
        // the model card's values (LFM 0.3 / top_k 64 / min_p 0.15 / rep 1.05,
        // Qwen 0.7 / 20 / 0.8 / rep 1.1, Gemma 1.0 / 64 / 0.95), and the SDK
        // seeds `generation_defaults` from it. The app used to send its own
        // copy of the cards here and drifted from the packs.
        // Local: load VAD/STT/TTS first, then LLM, then open the mic.

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
        // Omitted when null so the SDK derives it; sending the key at all is
        // what used to override the tuned policy.
        if (turnAsrSilenceHangoverMs != null)
          'turn_asr_silence_hangover_ms': turnAsrSilenceHangoverMs,

        // ── Streaming ASR (live captions) ──
        'asr_streaming': asrStreaming,
        'asr_partial_interval_ms': asrPartialIntervalMs,

        // ── Diagnostics ──
        'debug_timeline': debugTimeline,
    };
  }

  /// Resolve BundledModels/<name> paths and patch [config] so the agent loads
  /// VAD/STT/TTS/turn from the app bundle.
  ///
  /// The agent starts the local LLM itself, last in its load sequence.
  Future<Map<String, dynamic>> resolveLocalConfig(
    Map<String, dynamic> config,
  ) async {
    if (!useLocalBundles) return config;

    Future<String> pathFor(String name) async {
      final p = await TheStageFlutterSDK.get_bundled_engine_path(name);
      if (p == null || p.isEmpty) {
        throw StateError(
          'Bundled model missing: $name\n'
          'Place engines under ios/Runner/BundledModels/$name/ '
          'or use Hugging Face ids (default).',
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
