import 'dart:async';

import 'package:flutter/services.dart';

import 'thestage_flutter_sdk.dart';

// ---------------------------------------------------------------------------
// AgentNodeContext
// ---------------------------------------------------------------------------
class AgentNodeContext {
  AgentNodeContext({
    required this.nodeId,
    required this.state,
    required this.isGateOpen,
    required void Function(String port, String value) sendPort,
    required Stream<Map<String, dynamic>> portEvents,
  }) : _sendPort = sendPort,
       _portEvents = portEvents;

  final String nodeId;
  final String state;
  final bool isGateOpen;
  final void Function(String port, String value) _sendPort;
  final Stream<Map<String, dynamic>> _portEvents;

  void sendPort(String name, String value) => _sendPort(name, value);

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
// VLMCaptionNode
// ---------------------------------------------------------------------------
/// Example custom node that runs a local VLM for live captions.
class VLMCaptionNode extends TheStageAgentNode {
  VLMCaptionNode({
    this.id = 'vlm',
    this.runWhen = const ['idle', 'sleeping'],
    this.modelName = 'vlm_caption',
    required this.enginesPath,
    this.prompt = 'Describe briefly for the voice assistant.',
    this.device = 'npu',
    this.revision,
  });

  @override
  final String id;

  @override
  final List<String> runWhen;

  final String modelName;
  final String enginesPath;
  final String prompt;
  final String device;
  /// HF revision override. `null` → SDK ModelRevisionMap.
  final String? revision;

  bool _modelReady = false;
  final _pending = <String>[];
  final _captions = StreamController<String>.broadcast();
  AgentNodeContext? _ctx;

  Stream<String> get captions => _captions.stream;

  @override
  Future<void> onStart(AgentNodeContext context) async {
    _ctx = context;
    await TheStageFlutterSDK.start_model(
      model_name: modelName,
      engines_path: enginesPath,
      model_type: 'thestage_vl',
      device: device,
      revision: revision,
    );
    _modelReady = true;
  }

  @override
  Future<void> onStop() async {
    if (!_modelReady) return;
    await TheStageFlutterSDK.stop_model(model_name: modelName);
    _modelReady = false;
  }

  @override
  Future<void> onState(AgentNodeContext context, String state) async {
    _ctx = context;
    if (context.isGateOpen) await _drain();
  }

  /// Buffer an image path; drains when gate is open (idle/sleeping).
  Future<void> submitImage({required String path}) async {
    _pending.add(path);
    if (_ctx?.isGateOpen == true) await _drain();
  }

  Future<void> _drain() async {
    final ctx = _ctx;
    if (ctx == null || !_modelReady) return;
    final batch = List<String>.from(_pending);
    _pending.clear();
    for (final path in batch) {
      final results = await TheStageFlutterSDK.infer(
        model_name: modelName,
        input_json: {
          'prompt': prompt,
          'image': path,
        },
      );
      final caption = results.isEmpty
          ? ''
          : (results.first['text']?.toString() ?? '');
      if (caption.isNotEmpty) {
        _captions.add(caption);
        ctx.sendPort('vlm.caption', caption);
      }
    }
  }
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
  }) : _nodesChannel = nodesChannel,
       _portEvents = portEvents,
       _sendNodePort = sendNodePort;

  final MethodChannel _nodesChannel;
  final Stream<Map<String, dynamic>> _portEvents;
  final Future<void> Function(String nodeId, String port, String value)
  _sendNodePort;
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
