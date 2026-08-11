import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent_custom_nodes/backend/model_roster.dart';

class _FakeBackend implements ModelRosterBackend {
  final prefetchCalls = <String>[];
  final startCalls = <String>[];
  final stopCalls = <String>[];

  @override
  Future<String> prefetchEngines({
    required String repoId,
    String? modelType,
    String? revision,
  }) async {
    prefetchCalls.add(repoId);
    return '/cache/$repoId';
  }

  @override
  Future<void> startModel({
    required String modelName,
    required String enginesPath,
    required String modelType,
    String device = 'npu',
    String? revision,
  }) async {
    startCalls.add(modelName);
  }

  @override
  Future<void> stopModel({required String modelName}) async {
    stopCalls.add(modelName);
  }
}

void main() {
  test('prepare prefetches all; ensureHot starts subset; ephemeral stops',
      () async {
    final fake = _FakeBackend();
    final roster = ModelRoster(
      [
        ModelSlot(
          name: 'vad',
          enginesPath: 'vad-repo',
          modelType: 'silero_vad',
          policy: ModelPolicy.resident,
        ),
        ModelSlot(
          name: 'vlm',
          enginesPath: 'vlm-repo',
          modelType: 'thestage_vl',
          policy: ModelPolicy.ephemeral,
        ),
      ],
      backend: fake,
    );

    await roster.prepare();
    expect(fake.prefetchCalls, ['vad-repo', 'vlm-repo']);

    await roster.ensureHot(['vad']);
    expect(fake.startCalls, ['vad']);
    expect(roster.hot, {'vad'});

    final result = await roster.withEphemeral('vlm', () async => 42);
    expect(result, 42);
    expect(fake.startCalls, ['vad', 'vlm']);
    expect(fake.stopCalls, ['vlm']);
    expect(roster.hot, {'vad'});
  });

  test('withEphemeral stops even when body throws', () async {
    final fake = _FakeBackend();
    final roster = ModelRoster(
      [
        ModelSlot(
          name: 'vlm',
          enginesPath: 'vlm-repo',
          modelType: 'thestage_vl',
          policy: ModelPolicy.ephemeral,
        ),
      ],
      backend: fake,
    );
    await expectLater(
      roster.withEphemeral('vlm', () async => throw StateError('boom')),
      throwsStateError,
    );
    expect(fake.stopCalls, ['vlm']);
  });
}
