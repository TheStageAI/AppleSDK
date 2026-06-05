import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

/// Who authored a transcript line.
enum MessageRole { user, assistant, error }

/// One line in the conversation transcript.
///
/// `user` lines come from speech recognition (what you said);
/// `assistant` lines come from the LLM (what it replied).
class ChatMessage {
  ChatMessage({required this.role, required this.text});
  final MessageRole role;
  String text;
}

/// Bridges the voice agent's event stream to plain, typed UI state.
///
/// This is the ONE place that turns SDK events into things the screen draws,
/// so the data flow is easy to follow. The screen itself only renders these
/// fields and calls [start] / [stop] / [interrupt].
///
/// Event -> state mapping:
///
///   agent.events (kind):
///     state_changed      -> [state]              idle / loading / listening / ...
///     user_speech        -> [messages] (user)    ASR transcription of your turn
///     response_delta     -> [streamingResponse]  LLM reply, streamed token-by-token
///     response_complete  -> [messages] (assistant) final LLM reply
///     error              -> [error]
///     metrics            -> [vadLevel] (mic level) / [loadingModels] (startup loader)
///
///   TheStageFlutterSDK.on_progress:
///     download / extract / compile progress for the model currently loading
///     -> [downloadProgress], [loadPhase]
class VoiceAgentController extends ChangeNotifier {
  VoiceAgentController(this._agent) {
    _eventSub = _agent.events.listen(_onEvent);
    _progressSub = TheStageFlutterSDK.on_progress.listen(_onProgress);
  }

  final TheStageVoiceAgentFlutter _agent;
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  StreamSubscription<Map<String, dynamic>>? _progressSub;

  // -- Conversation -----------------------------------------------------
  /// Finalized transcript lines (user + assistant), oldest first.
  final List<ChatMessage> messages = [];

  /// The assistant reply currently being streamed (before it's finalized).
  /// Empty when the assistant isn't mid-sentence.
  String streamingResponse = '';

  // -- Agent status -----------------------------------------------------
  TheStageAgentState state = TheStageAgentState.idle;
  String? error;

  /// Live microphone activity while listening, 0..1.
  double vadLevel = 0.0;

  // -- Startup model loading -------------------------------------------
  /// Models in the order the SDK loads them (VAD, Whisper, NeuTTS, ...).
  /// Each is announced by a `metrics` event before its progress starts.
  final List<String> loadingModels = [];

  /// The model currently loading (the rest of [loadingModels] are done).
  String? currentLoadingModel;

  /// Download fraction (0..1) for [currentLoadingModel] while downloading.
  double downloadProgress = 0.0;

  /// Phase for [currentLoadingModel]: downloading / extracting / loading.
  String loadPhase = '';

  // -- Derived ----------------------------------------------------------
  bool get isRunning => state != TheStageAgentState.idle;
  bool get canInterrupt =>
      state == TheStageAgentState.thinking ||
      state == TheStageAgentState.speaking;

  // -- Commands ---------------------------------------------------------
  Future<void> start(Map<String, dynamic> config) async {
    error = null;
    notifyListeners();
    try {
      await _agent.start(config: config);
    } catch (e) {
      error = 'Failed to start: $e';
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _agent.stop();
    state = TheStageAgentState.idle;
    notifyListeners();
  }

  Future<void> interrupt() => _agent.interrupt();

  void clearError() {
    error = null;
    notifyListeners();
  }

  // -- Event -> state translation --------------------------------------
  void _onEvent(Map<String, dynamic> event) {
    switch (event['kind']?.toString()) {
      case 'state_changed':
        state = TheStageAgentState.fromString(
          event['state']?.toString() ?? 'idle',
        );
        if (state != TheStageAgentState.loading) _resetLoading();

      case 'user_speech': // ASR transcription -> user bubble
        messages.add(ChatMessage(
          role: MessageRole.user,
          text: event['text']?.toString() ?? '',
        ));

      case 'response_delta': // LLM token -> streaming bubble
        streamingResponse += event['delta']?.toString() ?? '';

      case 'response_complete': // final LLM reply -> assistant bubble
        final raw = event['text']?.toString() ?? '';
        final interrupted = event['interrupted'] == true;
        // Prefer the SDK's final text; fall back to what we streamed
        // (e.g. interrupted before the SDK emitted a final string).
        final text = raw.isNotEmpty ? raw : streamingResponse;
        if (text.isNotEmpty) {
          messages.add(ChatMessage(
            role: MessageRole.assistant,
            text: interrupted ? '$text …' : text,
          ));
        }
        streamingResponse = '';

      case 'error':
        error = event['message']?.toString();

      case 'metrics':
        final prob = (event['vad_prob'] as num?)?.toDouble();
        if (prob != null) vadLevel = prob;
        final model = event['loading_model']?.toString();
        if (model != null && model != currentLoadingModel) {
          currentLoadingModel = model;
          if (!loadingModels.contains(model)) loadingModels.add(model);
          downloadProgress = 0.0;
          loadPhase = '';
        }
    }
    notifyListeners();
  }

  void _onProgress(Map<String, dynamic> event) {
    // Progress always belongs to the model currently loading (loads are
    // sequential), so we apply it to [currentLoadingModel].
    downloadProgress = (event['progress'] as num?)?.toDouble() ?? 0.0;
    loadPhase = event['phase']?.toString() ?? '';
    notifyListeners();
  }

  void _resetLoading() {
    loadingModels.clear();
    currentLoadingModel = null;
    downloadProgress = 0.0;
    loadPhase = '';
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _progressSub?.cancel();
    super.dispose();
  }
}
