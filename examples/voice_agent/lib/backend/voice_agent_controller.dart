import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

import '../models/chat_message.dart';

// ============================================================================
// BACKEND layer — the ONE bridge between the native voice agent and the UI
// ============================================================================
// The native `TheStageVoiceAgentFlutter` runs the whole pipeline (mic → VAD →
// ASR → LLM → TTS → speaker) and emits a single stream of events. This class
// is the *only* place that:
//
//   1. SUBSCRIBES to those events (see constructor), and
//   2. TRANSLATES each event into plain, typed UI state (see [_onEvent]).
//
// The frontend never touches the SDK. It reads the fields below and calls
// [start] / [stop] / [interrupt]. Because this class is a [ChangeNotifier],
// any widget wrapped in an `AnimatedBuilder`/`ListenableBuilder` rebuilds when
// state changes.
//
// ───────────────────────── Event → state map ──────────────────────────────
//
//   agent.events['kind']        what it means          field(s) updated
//   ─────────────────────       ──────────────         ───────────────────
//   state_changed               agent FSM moved        [state]
//   user_request_partial   ◄ASR live caption           [partialTranscript]
//   user_request           ◄ASR finalized your turn    [messages] (user)
//   response_delta         ◄LLM streamed token         [streamingResponse]
//   response_done          ◄LLM final reply            [messages] (assistant)
//   tool_started           ◄Path A tool invoke         [messages] (tool)
//   tool_ended             ◄Path A tool result         [messages] (tool)
//   error                       something failed       [error]
//   metrics                     mic level / loader      [vadLevel] / loading*
//
//   TheStageFlutterSDK.on_progress  model download/extract/compile progress
//                                   → [downloadProgress], [loadPhase]
//
// ASR (what you say)  → user_request_partial → user_request   (▲ two events)
// LLM (what it says)  → response_delta…      → response_done   (▲ two events)
//
// In both flows the FIRST event feeds a *live* (streaming) bubble and the
// SECOND finalizes it into a permanent [messages] line. The frontend draws the
// live bubbles from [partialTranscript] / [streamingResponse] and the final
// ones from [messages]; see `ui/widgets/transcript_area.dart`.
// ============================================================================
class VoiceAgentController extends ChangeNotifier {
  VoiceAgentController(this._agent) {
    // (1) SUBSCRIBE. Two streams, two handlers, cancelled in [dispose].
    //   • agent.events    — the live conversation/pipeline events.
    //   • on_progress     — per-model download/extract/compile progress.
    _eventSub = _agent.events.listen(_onEvent);
    _progressSub = TheStageFlutterSDK.on_progress.listen(_onProgress);
  }

  final TheStageVoiceAgentFlutter _agent;
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  StreamSubscription<Map<String, dynamic>>? _progressSub;

  // ── Conversation state (rendered by the transcript) ──────────────────────

  /// Finalized transcript lines (user + assistant), oldest first.
  final List<ChatMessage> messages = [];

  /// The assistant reply currently being streamed token-by-token, before it's
  /// finalized into [messages]. Empty when the assistant isn't mid-sentence.
  String streamingResponse = '';

  /// Live (streaming-ASR) partial of what you're saying *right now*, before
  /// the turn ends and the final `user_request` line lands. Empty otherwise.
  String partialTranscript = '';

  // ── Agent status ─────────────────────────────────────────────────────────

  TheStageAgentState state = TheStageAgentState.idle;
  String? error;

  /// Live microphone activity while listening, 0..1 (drives the mic meter).
  double vadLevel = 0.0;

  // ── Startup model loading ────────────────────────────────────────────────

  /// Models in the order the SDK loads them (VAD, Whisper, NeuTTS, ...). Each
  /// is announced by a `metrics` event before its progress starts streaming.
  final List<String> loadingModels = [];

  /// The model currently loading (everything earlier in [loadingModels] is
  /// done). `null` once loading completes.
  String? currentLoadingModel;

  /// Download fraction (0..1) for [currentLoadingModel] while downloading.
  double downloadProgress = 0.0;

  /// Phase for [currentLoadingModel]: downloading / extracting / loading.
  String loadPhase = '';

  /// When true, agent may already be `listening` but we still keep the
  /// loading checklist up for a deferred model (local LFM after TTS).
  bool _holdLoading = false;

  TheStageAgentState? _agentStateWhileHeld;

  // ── Derived helpers the UI asks about ────────────────────────────────────

  bool get isRunning => state != TheStageAgentState.idle || _holdLoading;
  bool get isStartupLoading =>
      state == TheStageAgentState.loading || _holdLoading;
  bool get canInterrupt =>
      state == TheStageAgentState.thinking ||
      state == TheStageAgentState.tool_calling ||
      state == TheStageAgentState.speaking;

  // ── Commands (called by the UI) ──────────────────────────────────────────

  /// Flip UI into loading *before* heavy pre-work (e.g. starting the local
  /// LLM handle). Without this, Start looks dead for 10–15s while LFM loads.
  void beginStartup({String? firstModel, bool holdForDeferredLlm = false}) {
    error = null;
    state = TheStageAgentState.loading;
    _holdLoading = holdForDeferredLlm;
    _agentStateWhileHeld = null;
    loadingModels.clear();
    currentLoadingModel = firstModel;
    downloadProgress = 0.0;
    loadPhase = firstModel == null ? '' : 'loading';
    if (firstModel != null) loadingModels.add(firstModel);
    notifyListeners();
  }

  /// Show [model] as the active row after VAD/STT/TTS finished (deferred LFM).
  void beginDeferredModel(String model) {
    _holdLoading = true;
    if (!loadingModels.contains(model)) loadingModels.add(model);
    currentLoadingModel = model;
    downloadProgress = 0.0;
    loadPhase = 'loading';
    state = TheStageAgentState.loading;
    notifyListeners();
  }

  /// Clear the deferred loader and restore the agent's real FSM state.
  void finishDeferredLoad() {
    _holdLoading = false;
    _resetLoading();
    if (_agentStateWhileHeld != null) {
      state = _agentStateWhileHeld!;
      _agentStateWhileHeld = null;
    }
    notifyListeners();
  }

  void failStartup(Object e) {
    error = '$e';
    _holdLoading = false;
    _agentStateWhileHeld = null;
    state = TheStageAgentState.idle;
    _resetLoading();
    notifyListeners();
  }

  /// Start the agent with a fully-built config map (see `AgentConfig`/
  /// `VoiceAgentSettings.toConfig`). With `auto_listen: false` the native side
  /// loads models only — call [beginListening] after deferred LFM is ready.
  Future<void> start(Map<String, dynamic> config) async {
    error = null;
    if (state != TheStageAgentState.loading) {
      state = TheStageAgentState.loading;
    }
    notifyListeners();
    try {
      await _agent.start(config: config);
    } catch (e) {
      error = 'Failed to start: $e';
      _holdLoading = false;
      _agentStateWhileHeld = null;
      state = TheStageAgentState.idle;
      _resetLoading();
      notifyListeners();
      rethrow;
    }
  }

  /// Open the mic after deferred models finish (pairs with `auto_listen: false`).
  Future<void> beginListening() async {
    await _agent.beginListening();
  }

  /// Stop the agent and reset conversation UI.
  ///
  /// Native [TheStageSlidingWindowMemory] is destroyed with the agent, so the
  /// on-screen transcript must go too — otherwise follow-ups look like the
  /// model "forgot" / got stupid while the UI still shows the old chat.
  Future<void> stop() async {
    await _agent.stop();
    _holdLoading = false;
    _agentStateWhileHeld = null;
    state = TheStageAgentState.idle;
    messages.clear();
    partialTranscript = '';
    streamingResponse = '';
    _resetLoading();
    notifyListeners();
  }

  /// Barge-in: stop the agent mid-thought/mid-speech (only valid while
  /// [canInterrupt]).
  Future<void> interrupt() => _agent.interrupt();

  void clearError() {
    error = null;
    notifyListeners();
  }

  // ── (2) TRANSLATE: event → typed state ───────────────────────────────────
  // This is the heart of the bridge. Every case maps one SDK event onto the
  // fields above, then notifies listeners so the UI repaints.
  void _onEvent(Map<String, dynamic> event) {
    switch (event['kind']?.toString()) {
      case 'state_changed':
        final next = TheStageAgentState.fromString(
          event['state']?.toString() ?? 'idle',
        );
        if (_holdLoading && next != TheStageAgentState.loading) {
          // Agent finished VAD/STT/TTS and moved on, but LFM still loading —
          // keep the checklist; stash the real FSM state for later.
          _agentStateWhileHeld = next;
          state = TheStageAgentState.loading;
        } else {
          state = next;
          // Leaving `loading` means startup finished — clear the loader state.
          if (state != TheStageAgentState.loading) _resetLoading();
        }

      // ─── ASR path: what YOU said ───
      case 'user_request_partial':
        // Streaming ASR caption: grows as you speak. Feeds the live USER
        // bubble. Replaced wholesale each event (it's the full partial so far).
        partialTranscript = event['text']?.toString() ?? '';

      case 'user_request':
        // Turn ended: the authoritative transcript. Drop the live partial and
        // commit a permanent USER line.
        partialTranscript = '';
        messages.add(ChatMessage(
          role: MessageRole.user,
          text: event['text']?.toString() ?? '',
        ));

      // ─── LLM path: what the AGENT said ───
      case 'response_delta':
        // One streamed LLM token/chunk. Append to the live ASSISTANT bubble.
        streamingResponse += event['delta']?.toString() ?? '';

      case 'response_done':
        // LLM reply finished (or was interrupted). Commit a permanent
        // ASSISTANT line and clear the live stream.
        final raw = event['text']?.toString() ?? '';
        final interrupted = event['reason']?.toString() == 'interrupted' ||
            event['interrupted'] == true;
        // Prefer the SDK's authoritative final text; fall back to what we
        // streamed (e.g. interrupted before a final string was emitted).
        final text = raw.isNotEmpty ? raw : streamingResponse;
        if (text.isNotEmpty) {
          messages.add(ChatMessage(
            role: MessageRole.assistant,
            text: interrupted ? '$text …' : text,
          ));
        }
        streamingResponse = '';

      case 'tool_started':
        final name = event['name']?.toString() ?? 'tool';
        final args = event['arguments']?.toString() ?? '{}';
        messages.add(ChatMessage(
          role: MessageRole.tool,
          text: '⚙ $name\n$args',
          meta: {'name': name, 'phase': 'started', 'content': args},
        ));

      case 'tool_ended':
        final name = event['name']?.toString() ?? 'tool';
        final content = event['content']?.toString() ?? '';
        messages.add(ChatMessage(
          role: MessageRole.tool,
          text: '✓ $name →\n$content',
          meta: {'name': name, 'phase': 'ended', 'content': content},
        ));

      case 'error':
        error = event['message']?.toString();

      case 'metrics':
        // Two unrelated diagnostics ride on `metrics`:
        //   • vad_prob      — live mic level while listening.
        //   • loading_model — name of the model about to load (startup only).
        final prob = (event['vad_prob'] as num?)?.toDouble();
        if (prob != null) vadLevel = prob;
        var model = event['loading_model']?.toString();
        // Remap pre-label-fix SDK strings until the rebuilt xcframework ships.
        const legacy = {
          'NeuTTS (TTS)': 'TTS (qwen3-tts-12hz-0.6b-base)',
          'Whisper (STT)': 'STT (thewhisper-large-v3-turbo)',
          'VAD': 'VAD (silero-vad)',
          'Smart-Turn': 'Turn (smart-turn-v3)',
        };
        if (model != null && legacy.containsKey(model)) {
          model = legacy[model];
        }
        if (model != null && model != currentLoadingModel) {
          currentLoadingModel = model;
          if (!loadingModels.contains(model)) loadingModels.add(model);
          downloadProgress = 0.0;
          // Default until the first progress event arrives (cache hits
          // often jump straight to compiling).
          loadPhase = 'loading';
        }
    }
    notifyListeners();
  }

  /// Progress belongs to the model currently loading (loads are sequential).
  /// Friendly display names come from `metrics.loading_model`; this only
  /// updates phase / fraction so we don't clobber "VAD (…)" with "vad".
  void _onProgress(Map<String, dynamic> event) {
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
    // Mirror of the constructor: always release the subscriptions.
    _eventSub?.cancel();
    _progressSub?.cancel();
    super.dispose();
  }
}
