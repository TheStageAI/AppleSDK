import 'dart:async';

import 'package:flutter/services.dart';

// ---------------------------------------------------------------------------
// AgentNodeContext
// ---------------------------------------------------------------------------
class AgentNodeContext {
  AgentNodeContext({
    required this.nodeId,
    required this.state,
    required this.isGateOpen,
    required void Function(String port, String value) sendPort,
    required void Function(Map<String, dynamic> event) publishEvent,
    required Stream<Map<String, dynamic>> portEvents,
  }) : _sendPort = sendPort,
       _publishEvent = publishEvent,
       _portEvents = portEvents;

  final String nodeId;
  final String state;
  final bool isGateOpen;
  final void Function(String port, String value) _sendPort;
  final void Function(Map<String, dynamic> event) _publishEvent;
  final Stream<Map<String, dynamic>> _portEvents;

  /// Publish a value on a local port name. Native bus name is `$nodeId.$name`.
  void sendPort(String name, String value) => _sendPort(name, value);

  /// Inject a bus event. Supported kinds today: `USER_REQUEST` with `text`.
  void publishEvent(Map<String, dynamic> event) => _publishEvent(event);

  Stream<String> recvPort(String name) {
    final fullName = '$nodeId.$name';
    return _portEvents
        .where((event) => event['port'] == fullName)
        .map((event) => event['value']?.toString() ?? '');
  }
}

// ---------------------------------------------------------------------------
// TheStageAgentNode
// ---------------------------------------------------------------------------
/// Base class for Flutter custom voice-agent nodes.
///
/// Pass instances to [TheStageVoiceAgentFlutter.start] via `extraNodes:`.
/// Example nodes (VLM captions, event logs) live in the host app — not here.
abstract class TheStageAgentNode {
  String get id;
  List<String> get runWhen;

  Map<String, dynamic> toDescriptor() => {
    'id': id,
    'run_when': runWhen,
  };

  Future<void> onStart(AgentNodeContext context) async {}

  Future<void> onStop() async {}

  Future<void> onState(AgentNodeContext context, String state) async {}

  Future<void> onEvent(
    AgentNodeContext context,
    Map<String, dynamic> event,
  ) async {}
}

// ---------------------------------------------------------------------------
// VoiceAgentNodeDispatcher
// ---------------------------------------------------------------------------
class VoiceAgentNodeDispatcher {
  VoiceAgentNodeDispatcher({
    required MethodChannel nodesChannel,
    required Stream<Map<String, dynamic>> portEvents,
    required Future<void> Function(String nodeId, String port, String value)
    sendNodePort,
    required Future<void> Function(
      String nodeId,
      Map<String, dynamic> event,
    )
    publishNodeEvent,
  }) : _nodesChannel = nodesChannel,
       _portEvents = portEvents,
       _sendNodePort = sendNodePort,
       _publishNodeEvent = publishNodeEvent;

  final MethodChannel _nodesChannel;
  final Stream<Map<String, dynamic>> _portEvents;
  final Future<void> Function(String nodeId, String port, String value)
  _sendNodePort;
  final Future<void> Function(String nodeId, Map<String, dynamic> event)
  _publishNodeEvent;
  final Map<String, TheStageAgentNode> _nodes = {};

  void registerNodes(List<TheStageAgentNode> nodes) {
    _nodes
      ..clear()
      ..addEntries(nodes.map((node) => MapEntry(node.id, node)));
  }

  void installHandler() {
    _nodesChannel.setMethodCallHandler(_handleMethodCall);
  }

  void dispose() {
    _nodesChannel.setMethodCallHandler(null);
    _nodes.clear();
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    final args = _asMap(call.arguments);
    final nodeId = args['id']?.toString();
    if (nodeId == null) return;

    final node = _nodes[nodeId];
    if (node == null) return;

    final context = AgentNodeContext(
      nodeId: nodeId,
      state: args['state']?.toString() ?? 'idle',
      isGateOpen: args['is_gate_open'] == true,
      sendPort: (port, value) {
        unawaited(_sendNodePort(nodeId, port, value));
      },
      publishEvent: (event) {
        unawaited(_publishNodeEvent(nodeId, event));
      },
      portEvents: _portEvents,
    );

    switch (call.method) {
      case 'voice_agent.node_on_start':
        await node.onStart(context);
      case 'voice_agent.node_on_stop':
        await node.onStop();
      case 'voice_agent.node_on_state':
        await node.onState(context, context.state);
      case 'voice_agent.node_on_event':
        final event = _asMap(args['event']);
        await node.onEvent(context, event);
    }
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is! Map) return {};
    return value.map(
      (key, val) => MapEntry(key.toString(), val),
    );
  }
}
