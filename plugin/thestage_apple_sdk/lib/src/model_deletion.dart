import 'package:flutter/services.dart';

// ---------------------------------------------------------------------------
// ModelDeletion
// ---------------------------------------------------------------------------
/// What [TheStageFlutterSDK.delete_model] removed.
class ModelDeletion {
  /// Bytes freed on disk; 0 when nothing of the pack was on this device.
  final int freed_bytes;

  /// Revisions whose copies were removed, sorted.
  final List<String> revisions;

  const ModelDeletion({required this.freed_bytes, required this.revisions});

  factory ModelDeletion.fromMap(Map<Object?, Object?>? map) {
    final revisions = (map?['revisions'] as List<Object?>?) ?? const [];
    return ModelDeletion(
      freed_bytes: (map?['freed_bytes'] as num?)?.toInt() ?? 0,
      revisions: revisions.map((r) => r.toString()).toList(),
    );
  }

  @override
  String toString() =>
      'ModelDeletion(freed_bytes: $freed_bytes, revisions: $revisions)';
}

// ---------------------------------------------------------------------------
// ModelInUseException
// ---------------------------------------------------------------------------
/// The pack is loaded; nothing was removed. Stop it with
/// [TheStageFlutterSDK.stop_model] (each of [model_names]) and retry.
class ModelInUseException implements Exception {
  final String engines_path;

  /// Handles started with `start_model`; empty when a pipeline built
  /// directly in native code holds the pack.
  final List<String> model_names;
  final String message;

  const ModelInUseException({
    required this.engines_path,
    required this.model_names,
    required this.message,
  });

  @override
  String toString() => 'ModelInUseException: $message';
}

// ---------------------------------------------------------------------------
// ModelBusyException
// ---------------------------------------------------------------------------
/// A download, unpack or start of the pack is in flight; nothing was removed.
/// Retry once it has finished (or failed).
class ModelBusyException implements Exception {
  final String engines_path;
  final String message;

  const ModelBusyException({required this.engines_path, required this.message});

  @override
  String toString() => 'ModelBusyException: $message';
}

/// Map a `delete_model` refusal onto its typed exception; any other
/// failure comes back unchanged.
Exception deleteModelError(PlatformException error) {
  final details = error.details;
  if (details is! Map) return error;
  final enginesPath = details['engines_path']?.toString() ?? '';
  final message = details['message']?.toString() ?? error.message ?? '';
  switch (details['reason']) {
    case 'model_in_use':
      final names = details['model_names']?.toString() ?? '';
      return ModelInUseException(
        engines_path: enginesPath,
        model_names: names.isEmpty ? const [] : names.split(','),
        message: message,
      );
    case 'model_busy':
      return ModelBusyException(engines_path: enginesPath, message: message);
  }
  return error;
}
