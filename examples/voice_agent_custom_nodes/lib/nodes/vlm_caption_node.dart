import 'dart:async';

import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

/// Who owns `start_model` / `stop_model` for the VLM handle.
enum VlmLifecycle {
  /// Node starts/stops the model in [onStart] / [onStop].
  owned,

  /// Host [ModelRoster] owns residency; node only infers.
  external,
}

/// App-local example node: submit an image → caption stream + port.
class VLMCaptionNode extends TheStageAgentNode {
  VLMCaptionNode({
    this.id = 'vlm',
    // Quiet states only — never drain during thinking / speaking.
    this.runWhen = const ['idle', 'sleeping', 'listening'],
    required this.enginesPath,
    this.prompt = 'Describe briefly for the voice assistant.',
    this.device = 'npu',
    this.revision,
    this.lifecycle = VlmLifecycle.external,
  });

  @override
  final String id;

  @override
  final List<String> runWhen;

  final String enginesPath;
  final String prompt;
  final String device;
  final String? revision;
  final VlmLifecycle lifecycle;

  bool _modelReady = false;
  final _pending = <Map<String, Object>>[];
  final _captions = StreamController<String>.broadcast();
  AgentNodeContext? _ctx;

  Stream<String> get captions => _captions.stream;

  /// Mark the model ready when [lifecycle] is [VlmLifecycle.external].
  void markReady({required bool ready}) {
    _modelReady = ready;
  }

  @override
  Future<void> onStart(AgentNodeContext context) async {
    _ctx = context;
    if (lifecycle == VlmLifecycle.owned) {
      await TheStageFlutterSDK.start_model(
        model_name: id,
        engines_path: enginesPath,
        model_type: 'thestage_vl',
        device: device,
        revision: revision,
      );
      _modelReady = true;
    }
  }

  @override
  Future<void> onStop() async {
    if (lifecycle == VlmLifecycle.owned && _modelReady) {
      await TheStageFlutterSDK.stop_model(model_name: id);
    }
    _modelReady = false;
  }

  @override
  Future<void> onState(AgentNodeContext context, String state) async {
    _ctx = context;
    if (context.isGateOpen) await _drain();
  }

  Future<void> submitImage({required String path}) async {
    _pending.add({'image': path});
    if (_ctx?.isGateOpen == true) await _drain();
  }

  Future<void> submitImageBytes({required List<int> bytes}) async {
    _pending.add({'image_bytes': bytes});
    if (_ctx?.isGateOpen == true) await _drain();
  }

  Future<void> submitImageBase64({required String base64}) async {
    _pending.add({'image_base64': base64});
    if (_ctx?.isGateOpen == true) await _drain();
  }

  Future<void> _drain() async {
    final ctx = _ctx;
    if (ctx == null || !_modelReady) return;
    final batch = List<Map<String, Object>>.from(_pending);
    _pending.clear();
    for (final imageInput in batch) {
      final results = await TheStageFlutterSDK.infer(
        model_name: id,
        input_json: {
          'prompt': prompt,
          ...imageInput,
        },
      );
      final caption = results.isEmpty
          ? ''
          : (results.first['text']?.toString() ?? '');
      if (caption.isNotEmpty) {
        _captions.add(caption);
        // Local port name → bus `vlm.caption`
        ctx.sendPort('caption', caption);
      }
    }
  }
}
