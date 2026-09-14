// ---------------------------------------------------------------------------
// ModelComponentState / ModelPlacement
// ---------------------------------------------------------------------------
enum ModelComponentState { LOADED, OFFLOADED, LOADING, OFFLOADING }

enum ModelPlacement { AUTOMATIC, CPU, GPU, NEURAL_ENGINE, MIXED }

// ---------------------------------------------------------------------------
// ModelComponentStatus
// ---------------------------------------------------------------------------
class ModelComponentStatus {
  final String id;
  final String kind;
  final List<String> dependencies;
  final ModelComponentState state;
  final ModelPlacement placement;
  final bool can_offload;
  final int active_leases;

  const ModelComponentStatus({
    required this.id,
    required this.kind,
    this.dependencies = const [],
    required this.state,
    this.placement = ModelPlacement.AUTOMATIC,
    required this.can_offload,
    this.active_leases = 0,
  });

  bool get loaded => state == ModelComponentState.LOADED;

  factory ModelComponentStatus.from_json(Map<String, dynamic> json) {
    final raw_state = json['state'] as String?;
    final state = ModelComponentState.values.firstWhere(
      (s) => s.name == raw_state,
      orElse: () => (json['loaded'] == true)
          ? ModelComponentState.LOADED
          : ModelComponentState.OFFLOADED,
    );
    final raw_place = json['placement'] as String?;
    final placement = ModelPlacement.values.firstWhere(
      (p) => p.name == raw_place,
      orElse: () => ModelPlacement.AUTOMATIC,
    );
    return ModelComponentStatus(
      id: json['id'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      dependencies: (json['dependencies'] as List?)?.cast<String>() ?? const [],
      state: state,
      placement: placement,
      can_offload: json['can_offload'] as bool? ?? false,
      active_leases: (json['active_leases'] as num?)?.toInt() ?? 0,
    );
  }
}
