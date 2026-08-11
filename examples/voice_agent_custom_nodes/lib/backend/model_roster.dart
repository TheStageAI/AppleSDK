import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

/// Residency policy for a named ModelManager handle.
enum ModelPolicy {
  /// Stay in memory for the session.
  resident,

  /// Prefetch + compile to disk only; start later.
  warmDisk,

  /// Start for a work unit, stop when done.
  ephemeral,
}

class ModelSlot {
  ModelSlot({
    required this.name,
    required this.enginesPath,
    required this.modelType,
    this.policy = ModelPolicy.resident,
    this.device = 'npu',
    this.revision,
  });

  final String name;
  final String enginesPath;
  final String modelType;
  final ModelPolicy policy;
  final String device;
  final String? revision;
}

/// Backend used by [ModelRoster] (real SDK or fakes in tests).
abstract class ModelRosterBackend {
  Future<String> prefetchEngines({
    required String repoId,
    String? modelType,
    String? revision,
  });

  Future<void> startModel({
    required String modelName,
    required String enginesPath,
    required String modelType,
    String device = 'npu',
    String? revision,
  });

  Future<void> stopModel({required String modelName});
}

class SdkModelRosterBackend implements ModelRosterBackend {
  @override
  Future<String> prefetchEngines({
    required String repoId,
    String? modelType,
    String? revision,
  }) {
    return TheStageFlutterSDK.prefetch_engines(
      repo_id: repoId,
      model_type: modelType,
      revision: revision,
    );
  }

  @override
  Future<void> startModel({
    required String modelName,
    required String enginesPath,
    required String modelType,
    String device = 'npu',
    String? revision,
  }) async {
    await TheStageFlutterSDK.start_model(
      model_name: modelName,
      engines_path: enginesPath,
      model_type: modelType,
      device: device,
      revision: revision,
    );
  }

  @override
  Future<void> stopModel({required String modelName}) async {
    await TheStageFlutterSDK.stop_model(model_name: modelName);
  }
}

/// Sequences warm → hot without inventing a second model manager.
class ModelRoster {
  ModelRoster(
    this.slots, {
    ModelRosterBackend? backend,
  }) : _backend = backend ?? SdkModelRosterBackend();

  final List<ModelSlot> slots;
  final ModelRosterBackend _backend;
  final Set<String> hot = {};
  final Map<String, String> resolvedPaths = {};

  ModelSlot? slot(String name) {
    for (final s in slots) {
      if (s.name == name) return s;
    }
    return null;
  }

  /// Prefetch + compile every slot to disk.
  Future<void> prepare({
    void Function(String name, double progress)? onProgress,
  }) async {
    for (final s in slots) {
      onProgress?.call(s.name, 0);
      final path = await _backend.prefetchEngines(
        repoId: s.enginesPath,
        modelType: s.modelType,
        revision: s.revision,
      );
      resolvedPaths[s.name] = path.isNotEmpty ? path : s.enginesPath;
      onProgress?.call(s.name, 1);
    }
  }

  /// `start_model` for the named slots (and mark hot).
  Future<void> ensureHot(Iterable<String> names) async {
    for (final name in names) {
      final s = slot(name);
      if (s == null) continue;
      if (hot.contains(name)) continue;
      final path = resolvedPaths[name] ?? s.enginesPath;
      await _backend.startModel(
        modelName: s.name,
        enginesPath: path,
        modelType: s.modelType,
        device: s.device,
        revision: s.revision,
      );
      hot.add(name);
    }
  }

  /// `stop_model` for names that should leave memory.
  Future<void> release(Iterable<String> names) async {
    for (final name in names) {
      if (!hot.contains(name)) continue;
      await _backend.stopModel(modelName: name);
      hot.remove(name);
    }
  }

  /// Start → run → stop (compile cache keeps next start cheap).
  Future<T> withEphemeral<T>(
    String name,
    Future<T> Function() body,
  ) async {
    await ensureHot([name]);
    try {
      return await body();
    } finally {
      await release([name]);
    }
  }

  /// Offload [park] models, run an ephemeral [name], then restore [park].
  ///
  /// Use for VLM / other ANE-heavy bursts while the voice agent is in a
  /// quiet state (`idle` / `listening` / `sleeping`).
  Future<T> withEphemeralSwap<T>(
    String name, {
    required Iterable<String> park,
    required Future<T> Function() body,
  }) async {
    final parked = park.where(hot.contains).toList();
    await release(parked);
    try {
      return await withEphemeral(name, body);
    } finally {
      await ensureHot(parked);
    }
  }
}
