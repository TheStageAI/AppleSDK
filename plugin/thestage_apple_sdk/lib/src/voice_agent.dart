import 'dart:async';

import 'package:flutter/services.dart';

import 'agent_node.dart';
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
/// All orchestration runs natively — this class forwards lifecycle
/// commands and emits events for the UI to consume.
class TheStageVoiceAgentFlutter {
  static const MethodChannel _channel = MethodChannel(MethodChannels.main);
  static const MethodChannel _nodesChannel = MethodChannel(
    MethodChannels.voiceAgentNodes,
  );
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
  static const EventChannel _portsChannel = EventChannel(
    MethodChannels.voiceAgentPorts,
  );

  StreamSubscription? _eventSub;
  StreamSubscription? _portSub;
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _portController =
      StreamController<Map<String, dynamic>>.broadcast();
  VoiceAgentNodeDispatcher? _nodeDispatcher;

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

  TheStageAgentState get state => _state;

  Stream<Map<String, dynamic>> get events => _controller.stream;

  Stream<String> get llmDeltas => _llmDeltas;

  Stream<String> get transcripts => _transcripts;

  Stream<double> get vadProbabilities => _vadProbabilities;

  /// Multiplexed stream of `{port, value}` events from the native
  /// ``AgentPortRegistry`` (built-in aliases plus custom node ports).
  Stream<Map<String, dynamic>> get portEvents => _portController.stream;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  Future<void> start({
    required Map<String, dynamic> config,
    List<TheStageAgentNode> extraNodes = const [],
  }) async {
    _startListeningEvents();
    _startListeningPorts();

    final merged = Map<String, dynamic>.from(config);
    if (extraNodes.isNotEmpty) {
      merged['extra_nodes'] = extraNodes.map((n) => n.toDescriptor()).toList();
    }

    _nodeDispatcher?.dispose();
    _nodeDispatcher = VoiceAgentNodeDispatcher(
      nodesChannel: _nodesChannel,
      portEvents: portEvents,
      sendNodePort: _sendNodePort,
      publishNodeEvent: _publishNodeEvent,
    )..registerNodes(extraNodes)
      ..installHandler();

    await _channel.invokeMethod(MethodRoute.voiceAgentStart, merged);
  }

  Future<void> beginListening() async {
    await _channel.invokeMethod(MethodRoute.voiceAgentBeginListening);
  }

  Future<void> stop() async {
    await _channel.invokeMethod(MethodRoute.voiceAgentStop);
    _nodeDispatcher?.dispose();
    _nodeDispatcher = null;
    _state = TheStageAgentState.idle;
  }

  Future<void> interrupt() async {
    await _channel.invokeMethod(MethodRoute.voiceAgentInterrupt);
  }

  Future<void> say(String text) async {
    await _channel.invokeMethod(MethodRoute.voiceAgentSay, {'text': text});
  }

  /// Inject a text user turn (parity with Swift `send_request`).
  Future<void> sendRequest(String text) async {
    await _channel.invokeMethod(
      MethodRoute.voiceAgentSendRequest,
      {'text': text},
    );
  }

  Future<void> setVoice(String voice) async {
    await _channel.invokeMethod(
      MethodRoute.voiceAgentSetVoice,
      {'voice': voice},
    );
  }

  Future<void> clearHistory() async {
    await _channel.invokeMethod(MethodRoute.voiceAgentClearHistory);
  }

  /// Enroll or clear the speaker embedding used by speaker-id gating.
  Future<void> enrollSpeaker({
    List<double>? embedding,
    String? audioPath,
  }) async {
    if (audioPath != null) {
      throw UnsupportedError(
        'audioPath enrollment is not supported yet; pass embedding instead.',
      );
    }
    await _channel.invokeMethod(MethodRoute.voiceAgentEnrollSpeaker, {
      'embedding': embedding,
    });
  }

  /// Subscribe to a named agent port (`llm.delta`, `vad.probability`, or
  /// a custom node port such as `my_node.caption`).
  Stream<dynamic> subscribePort(String name) {
    return portEvents
        .where((event) => event['port'] == name)
        .map((event) => event['value']);
  }

  Future<void> updateInterruptConfig({
    int? interruptMinSpeechMs,
    int? interruptMinPlaybackMs,
    String? interruptMode,
    int? interruptOnsetMs,
    double? interruptThreshold,
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
    if (interruptOnsetMs != null) {
      args['interrupt_onset_ms'] = interruptOnsetMs;
    }
    if (interruptThreshold != null) {
      args['interrupt_threshold'] = interruptThreshold;
    }
    if (args.isEmpty) return;
    await _channel.invokeMethod(
      MethodRoute.voiceAgentUpdateInterruptConfig,
      args,
    );
  }

  void dispose() {
    _eventSub?.cancel();
    _portSub?.cancel();
    _nodeDispatcher?.dispose();
    _controller.close();
    _portController.close();
  }

  // -------------------------------------------------------------------------
  // Private
  // -------------------------------------------------------------------------

  Future<void> _sendNodePort(
    String nodeId,
    String port,
    String value,
  ) async {
    await _channel.invokeMethod(MethodRoute.voiceAgentSendNodePort, {
      'node_id': nodeId,
      'port': port,
      'value': value,
    });
  }

  Future<void> _publishNodeEvent(
    String nodeId,
    Map<String, dynamic> event,
  ) async {
    await _channel.invokeMethod(MethodRoute.voiceAgentPublishNodeEvent, {
      'node_id': nodeId,
      'event': event,
    });
  }

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

  void _startListeningPorts() {
    _portSub?.cancel();
    _portSub = _portsChannel.receiveBroadcastStream().listen(
      (event) {
        final map = (event as Map<Object?, Object?>).map(
          (k, v) => MapEntry(k.toString(), v),
        );
        _portController.add(map);
      },
      onError: (e) => _portController.addError(e),
    );
  }
}
