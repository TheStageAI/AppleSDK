import 'dart:async';

import 'package:flutter/services.dart';

import 'method_channels.dart';

// ---------------------------------------------------------------------------
// TheStageFlutterSDK
// ---------------------------------------------------------------------------
class TheStageFlutterSDK {
  static const MethodChannel _channel = MethodChannel(MethodChannels.main);
  static const EventChannel _progressChannel = EventChannel(
    MethodChannels.progress,
  );
  static const EventChannel _streamChannel = EventChannel(
    MethodChannels.ttsStream,
  );

  static StreamController<Map<String, dynamic>>? _streamEvents;
  static int _nextStreamOrdinal = 0;

  static void _ensureStreamChannel() {
    if (_streamEvents != null) return;
    _streamEvents = StreamController<Map<String, dynamic>>.broadcast();
    _streamChannel.receiveBroadcastStream().listen((event) {
      final map = event as Map<Object?, Object?>;
      _streamEvents!.add(
        map.map((key, value) => MapEntry(key.toString(), value)),
      );
    }, onError: (e) => _streamEvents!.addError(e));
  }

  static Stream<Map<String, dynamic>> get on_progress {
    return _progressChannel.receiveBroadcastStream().map((event) {
      final map = event as Map<Object?, Object?>;
      return map.map((key, value) => MapEntry(key.toString(), value));
    });
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  static Future<void> initialize({required String api_token}) async {
    await _channel.invokeMethod(
      MethodRoute.initialize,
      {'api_token': api_token},
    );
  }

  static Future<Map<String, dynamic>> start_model({
    required String model_name,
    required String engines_path,
    String? model_type,
    String device = 'gpu',
    String revision = 'main',
    Map<String, String>? devices,
    Map<String, dynamic>? config,
  }) async {
    final result = await _channel
        .invokeMethod<Map<Object?, Object?>>(MethodRoute.startModel, {
          'model_name': model_name,
          'engines_path': engines_path,
          'device': device,
          'revision': revision,
          if (model_type != null) 'model_type': model_type,
          if (devices != null) 'devices': devices,
          if (config != null) 'config': config,
        });
    return _asMap(result);
  }

  static Future<Map<String, dynamic>> stop_model({
    required String model_name,
  }) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      MethodRoute.stopModel,
      {'model_name': model_name},
    );
    return _asMap(result);
  }

  // ---------------------------------------------------------------------------
  // Batch Inference
  // ---------------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> infer({
    required String model_name,
    required Map<String, dynamic> input_json,
  }) async {
    final result = await _channel.invokeMethod<List<Object?>>(
      MethodRoute.infer,
      {
        'model_name': model_name,
        'input_json': input_json,
      },
    );
    if (result == null) return [];
    return result
        .map((item) => _asMap(item as Map<Object?, Object?>))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Streaming Inference
  // ---------------------------------------------------------------------------

  /// Stream inference results (TTS audio chunks or LLM text tokens).
  ///
  /// Audio chunks: `{kind: 'audio', audio: Float32List, sample_rate, is_final}`
  /// Text chunks: `{kind: 'text', delta: String, is_final}`
  ///
  /// `input_json` accepts model-specific keys. For TTS pipelines you may
  /// pass an optional nested `stream_config` map to tune codec-side audio
  /// chunking:
  ///
  /// ```dart
  /// TheStageFlutterSDK.infer_stream(
  ///   model_name: 'tts',
  ///   input_json: {
  ///     'text': 'Hello, world.',
  ///     'temperature': 0.8,
  ///     'stream_config': {
  ///       'frames_per_chunk': 25,
  ///       'first_frames_per_chunk': 25,
  ///       'lookforward': 5,
  ///       'lookback': 50,
  ///       'overlap_frames': 1,
  ///     },
  ///   },
  /// );
  /// ```
  ///
  /// Pass `text: ''` to start a push-mode stream driven by `send` /
  /// `finish_stream`. Unknown keys are ignored.
  static Stream<Map<String, dynamic>> infer_stream({
    required String model_name,
    required Map<String, dynamic> input_json,
    String? stream_id,
  }) async* {
    _ensureStreamChannel();
    final id = stream_id ?? _makeStreamId(model_name);
    await _channel.invokeMethod(MethodRoute.startStream, {
      'model_name': model_name,
      'input_json': input_json,
      'stream_id': id,
    });
    await for (final chunk in _streamEvents!.stream) {
      if (chunk['stream_id'] != id) continue;
      yield chunk;
      if (chunk['is_final'] == true) return;
    }
  }

  static Future<void> send({
    required String stream_id,
    required String text,
  }) async {
    await _channel.invokeMethod(MethodRoute.send, {
      'stream_id': stream_id,
      'text': text,
    });
  }

  static Future<void> finish_stream({required String stream_id}) async {
    await _channel.invokeMethod(MethodRoute.finishStream, {
      'stream_id': stream_id,
    });
  }

  static Future<void> stop_stream({required String stream_id}) async {
    await _channel.invokeMethod(MethodRoute.stopStream, {
      'stream_id': stream_id,
    });
  }

  // ---------------------------------------------------------------------------
  // Components
  // ---------------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> list_components({
    required String model_name,
  }) async {
    final result = await _channel.invokeMethod<List<Object?>>(
      MethodRoute.listComponents,
      {'model_name': model_name},
    );
    if (result == null) return [];
    return result
        .map((item) => _asMap(item as Map<Object?, Object?>))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> load_components({
    required String model_name,
    required List<String> component_ids,
  }) async {
    final result = await _channel.invokeMethod<List<Object?>>(
      MethodRoute.loadComponents,
      {'model_name': model_name, 'component_ids': component_ids},
    );
    if (result == null) return [];
    return result
        .map((item) => _asMap(item as Map<Object?, Object?>))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> unload_components({
    required String model_name,
    required List<String> component_ids,
  }) async {
    final result = await _channel.invokeMethod<List<Object?>>(
      MethodRoute.unloadComponents,
      {'model_name': model_name, 'component_ids': component_ids},
    );
    if (result == null) return [];
    return result
        .map((item) => _asMap(item as Map<Object?, Object?>))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  static Future<String?> get_bundled_engine_path(String filename) async {
    return await _channel.invokeMethod<String?>(
      MethodRoute.bundledEnginePath,
      {'filename': filename},
    );
  }

  static String _makeStreamId(String model_name) {
    _nextStreamOrdinal++;
    return '${model_name}_${DateTime.now().microsecondsSinceEpoch}_'
        '$_nextStreamOrdinal';
  }

  static Map<String, dynamic> _asMap(Map<Object?, Object?>? value) {
    if (value == null) return <String, dynamic>{};
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
}
