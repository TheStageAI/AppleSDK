import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'method_channels.dart';
import 'model_component.dart';

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
  static const EventChannel _logsChannel = EventChannel(MethodChannels.logs);

  static StreamController<Map<String, dynamic>>? _streamEvents;
  static StreamSubscription<dynamic>? _logSubscription;
  static int _nextStreamOrdinal = 0;

  /// Subscribe once so native ``TheStageLog`` lines appear in
  /// `flutter run` via [debugPrint] (Unified Logging does not).
  static void ensureDeveloperLogs() {
    if (_logSubscription != null) return;
    _logSubscription = _logsChannel.receiveBroadcastStream().listen(
      (event) {
        final map = (event as Map<Object?, Object?>).map(
          (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
        );
        final level = map['level'] ?? '';
        final category = map['category'] ?? '';
        final code = map['event'] ?? '';
        final message = map['message'] ?? '';
        debugPrint('[TheStage] $level $category $code $message');
      },
      onError: (_) {},
    );
  }

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

  /// [hf_token] is optional: an authenticated Hugging Face download gets the
  /// Hub's higher rate limits and faster transfer path. It is sent to
  /// huggingface.co only and never logged.
  static Future<void> initialize({
    required String api_token,
    String? hf_token,
  }) async {
    ensureDeveloperLogs();
    await _channel.invokeMethod(
      MethodRoute.initialize,
      {
        'api_token': api_token,
        if (hf_token != null && hf_token.isNotEmpty) 'hf_token': hf_token,
      },
    );
  }

  static Future<Map<String, dynamic>> start_model({
    required String model_name,
    required String engines_path,
    String? model_type,
    String device = 'npu',
    /// HF revision override. `null` → SDK ``ModelRevisionMap`` for this build.
    String? revision,
    Map<String, String>? devices,
    Map<String, dynamic>? config,
  }) async {
    final result = await _channel
        .invokeMethod<Map<Object?, Object?>>(MethodRoute.startModel, {
          'model_name': model_name,
          'engines_path': engines_path,
          'device': device,
          if (revision != null) 'revision': revision,
          if (model_type != null) 'model_type': model_type,
          if (devices != null) 'devices': devices,
          if (config != null) 'config': config,
        });
    return _asMap(result);
  }

  static Future<Map<String, dynamic>> start_asr_model({
    required String model_name,
    required String engines_path,
    String device = 'npu',
    String? revision,
    Map<String, String>? devices,
    Map<String, dynamic>? config,
  }) {
    return start_model(
      model_name: model_name,
      engines_path: engines_path,
      model_type: 'thestage_asr',
      device: device,
      revision: revision,
      devices: devices,
      config: config,
    );
  }

  static Future<Map<String, dynamic>> start_tts_model({
    required String model_name,
    required String engines_path,
    String device = 'npu',
    String? revision,
    Map<String, String>? devices,
    Map<String, dynamic>? config,
  }) {
    return start_model(
      model_name: model_name,
      engines_path: engines_path,
      model_type: 'thestage_tts',
      device: device,
      revision: revision,
      devices: devices,
      config: config,
    );
  }

  static Future<Map<String, dynamic>> start_llm_model({
    required String model_name,
    required String engines_path,
    String device = 'npu',
    String? revision,
    Map<String, String>? devices,
    Map<String, dynamic>? config,
  }) {
    return start_model(
      model_name: model_name,
      engines_path: engines_path,
      model_type: 'thestage_llm',
      device: device,
      revision: revision,
      devices: devices,
      config: config,
    );
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

  /// Download / extract engines to disk without loading into memory.
  /// Returns the local engines directory path.
  static Future<String> prefetch_engines({
    required String repo_id,
    String? model_type,
    String? revision,
    Map<String, dynamic>? config,
  }) async {
    final result = await _channel.invokeMethod<String>(
      MethodRoute.prefetchEngines,
      {
        'repo_id': repo_id,
        if (model_type != null) 'model_type': model_type,
        if (revision != null) 'revision': revision,
        if (config != null) 'config': config,
      },
    );
    return result ?? '';
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
  /// Text chunks (no tools): `{kind: 'text', delta: String, is_final}`
  /// LLM tools path (Path B): `{kind: 'text_delta'|'thinking_delta'|'tool_call'|'tool_result'|'final', ...}`
  /// — `tool_call` includes `name` + `arguments`; `final` may include raw assistant text in `delta`.
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
  /// Pass `text: ''` to start a push-mode TTS stream driven by `send` /
  /// `finish_stream`. For LLM / VLM, pass a non-empty `prompt` (and for
  /// VLM an `image` / `image_base64` / …) — that routes to one-shot
  /// `infer_stream` token deltas (`delta` / `is_final`), not the TTS
  /// push streamer. Unknown keys are ignored.
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

  static Future<String> open_push_stream({
    required String model_name,
    required String kind,
    Map<String, dynamic> input_json = const {},
    String? stream_id,
  }) async {
    _ensureStreamChannel();
    final id = stream_id ?? _makeStreamId(model_name);
    await _channel.invokeMethod(MethodRoute.startStream, {
      'model_name': model_name,
      'input_json': input_json,
      'stream_id': id,
      'kind': kind,
    });
    return id;
  }

  static Stream<Map<String, dynamic>> events_for(String stream_id) {
    _ensureStreamChannel();
    return _streamEvents!.stream.where(
      (chunk) => chunk['stream_id'] == stream_id,
    );
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

  static Future<void> send_pcm({
    required String stream_id,
    required Float32List pcm,
  }) async {
    await _channel.invokeMethod(MethodRoute.send, {
      'stream_id': stream_id,
      'pcm': pcm,
    });
  }

  static Future<void> flush_stream({required String stream_id}) async {
    await _channel.invokeMethod(MethodRoute.flush, {
      'stream_id': stream_id,
    });
  }

  static Future<Map<String, dynamic>> close_stream({
    required String stream_id,
  }) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      MethodRoute.finishStream,
      {'stream_id': stream_id},
    );
    return _asMap(result);
  }

  static Future<void> finish_stream({required String stream_id}) async {
    await close_stream(stream_id: stream_id);
  }

  static Future<void> cancel_stream({required String stream_id}) async {
    await _channel.invokeMethod(MethodRoute.stopStream, {
      'stream_id': stream_id,
    });
  }

  static Future<void> stop_stream({required String stream_id}) async {
    await cancel_stream(stream_id: stream_id);
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

  static Future<List<ModelComponentStatus>> components({
    required String model_name,
  }) async {
    final rows = await list_components(model_name: model_name);
    return rows.map(ModelComponentStatus.from_json).toList();
  }

  static Future<List<Map<String, dynamic>>> load_components({
    required String model_name,
    List<String> component_ids = const [],
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
    List<String> component_ids = const [],
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

  /// Process memory as iOS accounts it. `footprint_mb` is `phys_footprint`
  /// (the metric the jetsam killer and Xcode's gauge use — counts compressed
  /// and IOKit/ANE memory); `resident_mb` is RSS (smaller, diagnostic only).
  /// Returns `null` on platforms that can't report it.
  static Future<Map<String, double>?> memory_footprint() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      MethodRoute.memoryFootprint,
    );
    if (result == null) return null;
    final map = _asMap(result);
    final footprint = (map['footprint_mb'] as num?)?.toDouble();
    final resident = (map['resident_mb'] as num?)?.toDouble();
    if (footprint == null || footprint < 0) return null;
    return {
      'footprint_mb': footprint,
      if (resident != null && resident >= 0) 'resident_mb': resident,
    };
  }

  static Future<List<Map<String, dynamic>>> list_model_cache() async {
    final result = await _channel.invokeMethod<List<Object?>>(
      MethodRoute.cacheList,
    );
    if (result == null) return [];
    return result
        .map((item) => _asMap(item as Map<Object?, Object?>))
        .toList();
  }

  static Future<bool> verify_model_cache(String key) async {
    return await _channel.invokeMethod<bool>(
          MethodRoute.cacheVerify,
          {'key': key},
        ) ??
        false;
  }

  static Future<bool> repair_model_cache(String key) async {
    return await _channel.invokeMethod<bool>(
          MethodRoute.cacheRepair,
          {'key': key},
        ) ??
        false;
  }

  static Future<void> repair_all_model_cache() async {
    await _channel.invokeMethod(MethodRoute.cacheRepairAll);
  }

  static Future<Map<String, dynamic>?> previous_launch() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      MethodRoute.previousLaunch,
    );
    if (result == null) return null;
    return _asMap(result);
  }

  static Future<Map<String, int>> field_counters() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      MethodRoute.fieldCounters,
    );
    final map = _asMap(result);
    return map.map((key, value) => MapEntry(key, (value as num).toInt()));
  }

  static Future<Map<String, bool>> durability_flags() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      MethodRoute.durabilityFlags,
    );
    final map = _asMap(result);
    return map.map((key, value) => MapEntry(key, value == true));
  }

  static Future<Map<String, bool>> set_durability_flag(
    String name,
    bool value,
  ) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      MethodRoute.setDurabilityFlag,
      {'name': name, 'value': value},
    );
    final map = _asMap(result);
    return map.map((key, value) => MapEntry(key, value == true));
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
