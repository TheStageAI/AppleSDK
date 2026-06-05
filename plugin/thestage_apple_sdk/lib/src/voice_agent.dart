import 'dart:async';

import 'package:flutter/services.dart';

import 'method_channels.dart';

// ---------------------------------------------------------------------------
// TheStageAgentState
// ---------------------------------------------------------------------------
enum TheStageAgentState {
  idle,
  loading,
  sleeping,
  listening,
  thinking,
  speaking;

  static TheStageAgentState fromString(String value) {
    return TheStageAgentState.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TheStageAgentState.idle,
    );
  }
}

// ---------------------------------------------------------------------------
// TheStageVoiceAgentFlutter
// ---------------------------------------------------------------------------
/// Flutter bridge for TheStageVoiceAgent (Swift SDK).
///
/// All orchestration runs natively — this class just forwards lifecycle
/// commands and emits events for the UI to consume.
///
/// Usage:
/// ```dart
/// final agent = TheStageVoiceAgentFlutter();
/// agent.events.listen((event) => handleEvent(event));
/// await agent.start(config: { ... });
/// // ...
/// await agent.stop();
/// ```
class TheStageVoiceAgentFlutter {
  static const MethodChannel _channel = MethodChannel(MethodChannels.main);
  static const EventChannel _eventChannel = EventChannel(
    MethodChannels.voiceAgentEvents,
  );
  static const EventChannel _llmDeltasChannel = EventChannel(
    MethodChannels.voiceAgentLLMDeltas,
  );
  static const EventChannel _transcriptsChannel = EventChannel(
    MethodChannels.voiceAgentTranscripts,
  );
  static const EventChannel _vadProbsChannel = EventChannel(
    MethodChannels.voiceAgentVADProbabilities,
  );

  StreamSubscription? _eventSub;
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  // Lazy `broadcast` views over the typed EventChannels so multiple
  // widgets can listen at once. Each one is backed by an `AgentConnector`
  // on the Swift side; the native handler creates / tears the connector
  // down based on Dart subscription state, so leaving these unused costs
  // nothing.
  late final Stream<String> _llmDeltas = _llmDeltasChannel
      .receiveBroadcastStream()
      .map((e) => e.toString());
  late final Stream<String> _transcripts = _transcriptsChannel
      .receiveBroadcastStream()
      .map((e) => e.toString());
  late final Stream<double> _vadProbabilities = _vadProbsChannel
      .receiveBroadcastStream()
      .map((e) => (e as num).toDouble());

  TheStageAgentState _state = TheStageAgentState.idle;

  // -------------------------------------------------------------------------
  // Public Getters
  // -------------------------------------------------------------------------

  /// Current agent state.
  TheStageAgentState get state => _state;

  /// Aggregate stream of agent events (state changes, transcripts, deltas,
  /// errors, ...). Kept for back-compat; new code can use the typed streams
  /// below for cleaner widget plumbing.
  Stream<Map<String, dynamic>> get events => _controller.stream;

  /// Stream of LLM token deltas for the current reply. Each value is the
  /// incremental chunk to append to the assistant text bubble. Backed by the
  /// `agent.llm_deltas` `AgentChannel` on the native side, so multiple Dart
  /// listeners are first-class (fan-out is handled in Swift).
  Stream<String> get llmDeltas => _llmDeltas;

  /// Stream of finalized user transcripts, one per turn. May fire with an
  /// empty string when the user said nothing recognisable - filter on
  /// `text.isNotEmpty` in your widget if that's noise.
  Stream<String> get transcripts => _transcripts;

  /// Per-frame VAD probability ([0.0, 1.0]). Roughly one value every 32 ms.
  /// Useful for level meters / debug overlays in the UI; fan-out is handled
  /// natively, so multiple widgets can subscribe at once.
  Stream<double> get vadProbabilities => _vadProbabilities;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Start the voice agent with the given configuration.
  ///
  /// Config keys map 1:1 to TheStageAgentConfig fields:
  ///
  /// Models (HF repo IDs or local paths):
  /// - `vad`: String — Silero VAD bundle
  /// - `stt`: String — Whisper bundle
  /// - `tts`: String — NeuTTS bundle
  /// - `tts_voice`: String — voice preset id (default `paul`)
  /// - `wake_word`: String? — wake-word bundle (null = disabled)
  ///
  /// LLM:
  /// - `llm_provider`: 'local' | 'openai_compatible'
  /// - `llm_model`: String (model name/path)
  /// - `llm_endpoint`: String? (URL for cloud)
  /// - `llm_api_key`: String? (for cloud)
  /// - `system_prompt`: String
  /// - `max_tokens`: int
  /// - `temperature`: double
  ///
  /// Compute device routing (default `"npu"` everywhere):
  /// - `vad_device`: String — `"npu"` | `"gpu"` | `"cpu"`
  /// - `stt_device`: String — coarse default for Whisper
  /// - `stt_devices`: Map<String, String>? — per-module override,
  ///   e.g. `{ "melspec": "npu", "encoder": "npu", "decoder": "gpu" }`
  /// - `tts_device`: String — coarse default for NeuTTS
  /// - `tts_devices`: Map<String, String>? — per-module override,
  ///   e.g. `{ "llm": "npu", "neucodec": "npu" }`
  /// - `stt_revision`: String — HF branch/tag (default `develop`)
  /// - `tts_revision`: String — HF branch/tag (default `develop`)
  ///
  /// VAD / endpointing:
  /// - `vad_threshold`: double
  /// - `silence_timeout_ms`: int
  /// - `pre_roll_ms`: int
  /// - `speculative_whisper`: bool — start STT during the silence
  ///   window so it's usually ready before end-of-turn (default true)
  ///
  /// Interruptions / AEC:
  /// - `allow_interruptions`: bool
  /// - `interrupt_mode`: 'speech_only' | 'wake_word'
  /// - `interrupt_min_speech_ms`: int
  /// - `aec_enabled`: bool — VPIO (iOS); set false on macOS
  /// - `stt_language`: String — Whisper language code (default `en`)
  Future<void> start({required Map<String, dynamic> config}) async {
    _startListeningEvents();
    await _channel.invokeMethod(MethodRoute.voiceAgentStart, config);
  }

  /// Stop the voice agent and release all resources.
  Future<void> stop() async {
    await _channel.invokeMethod(MethodRoute.voiceAgentStop);
    _state = TheStageAgentState.idle;
  }

  /// Interrupt the current response (cancel LLM + TTS).
  Future<void> interrupt() async {
    await _channel.invokeMethod(MethodRoute.voiceAgentInterrupt);
  }

  /// Speak text directly, bypassing LLM.
  Future<void> say(String text) async {
    await _channel.invokeMethod(MethodRoute.voiceAgentSay, {'text': text});
  }

  /// Change the TTS voice at runtime.
  Future<void> setVoice(String voice) async {
    await _channel.invokeMethod(
      MethodRoute.voiceAgentSetVoice,
      {'voice': voice},
    );
  }

  /// Clear conversation history.
  Future<void> clearHistory() async {
    await _channel.invokeMethod(MethodRoute.voiceAgentClearHistory);
  }

  /// Hot-update interrupt-related knobs on a running agent. Any `null`
  /// argument is left untouched on the native side. Use this from settings
  /// sliders so the user sees the new value applied immediately, without
  /// having to stop+start the agent.
  ///
  /// - `interruptMinSpeechMs`: sustained speech in ms required to fire
  ///   barge-in during `.speaking` / `.thinking`.
  /// - `interruptMinPlaybackMs`: AEC-converge grace at the start of every
  ///   TTS turn during which barge-in detection is suppressed.
  /// - `interruptMode`: `'none'` | `'speech_only'` | `'wake_word'`.
  Future<void> updateInterruptConfig({
    int? interruptMinSpeechMs,
    int? interruptMinPlaybackMs,
    String? interruptMode,
  }) async {
    final args = <String, dynamic>{};
    if (interruptMinSpeechMs != null) {
      args['interrupt_min_speech_ms'] = interruptMinSpeechMs;
    }
    if (interruptMinPlaybackMs != null) {
      args['interrupt_min_playback_ms'] = interruptMinPlaybackMs;
    }
    if (interruptMode != null) {
      args['interrupt_mode'] = interruptMode;
    }
    if (args.isEmpty) return;
    await _channel.invokeMethod(
      MethodRoute.voiceAgentUpdateInterruptConfig,
      args,
    );
  }

  /// Dispose resources. Call when done with the agent.
  void dispose() {
    _eventSub?.cancel();
    _controller.close();
  }

  // -------------------------------------------------------------------------
  // Private
  // -------------------------------------------------------------------------

  void _startListeningEvents() {
    _eventSub?.cancel();
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        final map = (event as Map<Object?, Object?>).map(
          (k, v) => MapEntry(k.toString(), v),
        );

        if (map['kind'] == 'state_changed') {
          final stateStr = map['state']?.toString() ?? 'idle';
          _state = TheStageAgentState.fromString(stateStr);
        }

        _controller.add(map);
      },
      onError: (e) => _controller.addError(e),
    );
  }
}
