import 'dart:async';

import 'package:flutter/services.dart';

import 'ts_agent_node.dart';
import 'method_channels.dart';

// ---------------------------------------------------------------------------
// TSAgentState
// ---------------------------------------------------------------------------
enum TSAgentState {
  idle,
  loading,
  sleeping,
  listening,
  thinking,
  tool_calling,
  speaking;

  static TSAgentState fromString(String value) {
    return TSAgentState.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TSAgentState.idle,
    );
  }
}

// ---------------------------------------------------------------------------
// TSVoiceAgent
// ---------------------------------------------------------------------------
/// Flutter bridge for TheStageVoiceAgent (Swift SDK).
///
/// All orchestration runs natively — this class forwards lifecycle
/// commands and emits events for the UI to consume.
class TSVoiceAgent {
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
  static const EventChannel _ttsLevelsChannel = EventChannel(
    MethodChannels.voiceAgentTTSLevels,
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
  late final Stream<double> _ttsLevels = _ttsLevelsChannel
      .receiveBroadcastStream()
      .map((e) => (e as num).toDouble());

  TSAgentState _state = TSAgentState.idle;

  // -------------------------------------------------------------------------
  // Public Getters
  // -------------------------------------------------------------------------

  TSAgentState get state => _state;

  Stream<Map<String, dynamic>> get events => _controller.stream;

  Stream<String> get llm_deltas => _llmDeltas;

  Stream<String> get transcripts => _transcripts;

  Stream<double> get vad_probabilities => _vadProbabilities;

  Stream<double> get tts_levels => _ttsLevels;

  /// Multiplexed stream of `{port, value}` events from the native
  /// ``AgentPortRegistry`` (built-in aliases plus custom node ports).
  Stream<Map<String, dynamic>> get port_events => _portController.stream;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  Map<String, dynamic> capabilities = const {};

  Future<Map<String, dynamic>> start({
    required Map<String, dynamic> config,
    List<TSAgentNode> extra_nodes = const [],
    bool require_full_stack = false,
  }) async {
    _startListeningEvents();
    _startListeningPorts();

    final merged = Map<String, dynamic>.from(config);
    if (extra_nodes.isNotEmpty) {
      merged['extra_nodes'] = extra_nodes.map((n) => n.toDescriptor()).toList();
    }

    _nodeDispatcher?.dispose();
    _nodeDispatcher = VoiceAgentNodeDispatcher(
      nodesChannel: _nodesChannel,
      portEvents: port_events,
      sendNodePort: _sendNodePort,
      publishNodeEvent: _publishNodeEvent,
    )..registerNodes(extra_nodes)
      ..installHandler();

    if (require_full_stack) {
      merged['require_full_stack'] = true;
    }
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      MethodRoute.voiceAgentStart,
      merged,
    );
    capabilities = result == null
        ? <String, dynamic>{}
        : result.map((key, value) => MapEntry(key.toString(), value));
    return capabilities;
  }

  Future<void> begin_listening() async {
    await _channel.invokeMethod(MethodRoute.voiceAgentBeginListening);
  }

  Future<void> stop() async {
    await _channel.invokeMethod(MethodRoute.voiceAgentStop);
    _nodeDispatcher?.dispose();
    _nodeDispatcher = null;
    _state = TSAgentState.idle;
  }

  Future<void> interrupt() async {
    await _channel.invokeMethod(MethodRoute.voiceAgentInterrupt);
  }

  Future<void> say(String text) async {
    await _channel.invokeMethod(MethodRoute.voiceAgentSay, {'text': text});
  }

  /// Inject a text user turn (parity with Swift `send_request`).
  Future<void> send_request(String text) async {
    await _channel.invokeMethod(
      MethodRoute.voiceAgentSendRequest,
      {'text': text},
    );
  }

  /// Hot-swap the TTS voice at runtime.
  ///
  /// Same shape as the standalone `TTSPipeline.set_voice(voice_dir:...)`:
  /// pass any subset of [voice_id], [voice_dir] and [language]. `null`
  /// fields are left unchanged on the agent config.
  ///
  /// ```dart
  /// await agent.set_voice(voice_id: 'paul');
  /// await agent.set_voice(voice_dir: '/path/to/prepared_pack');
  /// await agent.set_voice(voice_id: 'paul', language: 'french');
  /// ```
  Future<void> set_voice({
    String? voice_id,
    String? voice_dir,
    String? language,
  }) async {
    final args = <String, dynamic>{};
    if (voice_id != null) args['voice_id'] = voice_id;
    if (voice_dir != null) args['voice_dir'] = voice_dir;
    if (language != null) args['language'] = language;
    if (args.isEmpty) return;
    await _channel.invokeMethod(MethodRoute.voiceAgentSetVoice, args);
  }

  Future<void> clear_history() async {
    await _channel.invokeMethod(MethodRoute.voiceAgentClearHistory);
  }

  /// Hot-swap the LLM system prompt for subsequent turns (no agent restart).
  Future<void> set_system_prompt(String prompt) async {
    await _channel.invokeMethod(
      MethodRoute.voiceAgentSetSystemPrompt,
      {'system_prompt': prompt},
    );
  }

  /// Enroll or clear the speaker embedding used by speaker-id gating.
  Future<void> enroll_speaker({
    List<double>? embedding,
    String? audio_path,
  }) async {
    if (audio_path != null) {
      throw UnsupportedError(
        'audio_path enrollment is not supported yet; pass embedding instead.',
      );
    }
    await _channel.invokeMethod(MethodRoute.voiceAgentEnrollSpeaker, {
      'embedding': embedding,
    });
  }

  /// Subscribe to a named agent port (`llm.delta`, `vad.probability`, or
  /// a custom node port such as `my_node.caption`).
  Stream<dynamic> subscribe_port(String name) {
    return port_events
        .where((event) => event['port'] == name)
        .map((event) => event['value']);
  }

  Future<void> update_interrupt_config({
    int? interrupt_min_speech_ms,
    int? interrupt_min_playback_ms,
    String? interrupt_mode,
    int? interrupt_onset_ms,
    double? interrupt_threshold,
  }) async {
    final args = <String, dynamic>{};
    if (interrupt_min_speech_ms != null) {
      args['interrupt_min_speech_ms'] = interrupt_min_speech_ms;
    }
    if (interrupt_min_playback_ms != null) {
      args['interrupt_min_playback_ms'] = interrupt_min_playback_ms;
    }
    if (interrupt_mode != null) {
      args['interrupt_mode'] = interrupt_mode;
    }
    if (interrupt_onset_ms != null) {
      args['interrupt_onset_ms'] = interrupt_onset_ms;
    }
    if (interrupt_threshold != null) {
      args['interrupt_threshold'] = interrupt_threshold;
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
          _state = TSAgentState.fromString(stateStr);
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
