import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thestage_apple_sdk/src/asr_engine.dart';
import 'package:thestage_apple_sdk/src/inference_types.dart';

Map<String, dynamic> _load_schema() {
  final candidates = [
    'Qlip.SDK/schema/inference_types.json',
    '../../Qlip.SDK/schema/inference_types.json',
    '../Qlip.SDK/schema/inference_types.json',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
  }
  throw StateError(
    'schema/inference_types.json not found from ${Directory.current.path}',
  );
}

void _assert_fields(String name, List<String> dart_fields, Map schema) {
  final types = schema['types'] as Map;
  final fields = (types[name] as Map)['fields'] as Map;
  expect(
    dart_fields.toSet(),
    equals(fields.keys.toSet()),
    reason: '$name drifted from schema',
  );
}

void main() {
  late Map<String, dynamic> schema;

  setUpAll(() {
    schema = _load_schema();
  });

  test('ASRStreamingAlgorithm matches the schema', () {
    final enums = schema['enums'] as Map;
    expect(
      ASRStreamingAlgorithm.values.map((e) => e.name).toSet(),
      equals((enums['ASRStreamingAlgorithm'] as List).toSet()),
    );
    expect(
      ASRStreamingAlgorithm.values,
      contains(ASRStreamingAlgorithm.THESTAGE_V5),
    );
  });

  test('enum cases match schema', () {
    final enums = schema['enums'] as Map;
    expect(
      ASRTimestampMode.values.map((e) => e.name).toSet(),
      equals((enums['ASRTimestampMode'] as List).toSet()),
    );
    expect(
      ASRTextContext.values.map((e) => e.name).toSet(),
      equals((enums['ASRTextContext'] as List).toSet()),
    );
    expect(
      ASREndpointCommit.values.map((e) => e.name).toSet(),
      equals((enums['ASREndpointCommit'] as List).toSet()),
    );
    expect(
      ASRConfirmationScope.values.map((e) => e.name).toSet(),
      equals((enums['ASRConfirmationScope'] as List).toSet()),
    );
  });

  test('stored fields match schema', () {
    _assert_fields(
      'ASRStreamingConfig',
      ASRStreamingConfig.field_names,
      schema,
    );
    _assert_fields(
      'ASRGenerationConfig',
      ASRGenerationConfig.field_names,
      schema,
    );
    _assert_fields('ASRResult', ASRResult.field_names, schema);
    _assert_fields('ASRMetrics', ASRMetrics.field_names, schema);
    _assert_fields('ASRTokenStats', ASRTokenStats.field_names, schema);
    _assert_fields('SamplingParams', SamplingParams.field_names, schema);
    _assert_fields(
      'LLMGenerationConfig',
      LLMGenerationConfig.field_names,
      schema,
    );
    _assert_fields('LLMResult', LLMResult.field_names, schema);
    _assert_fields(
      'TTSGenerationConfig',
      TTSGenerationConfig.field_names,
      schema,
    );
    _assert_fields('TTSResult', TTSResult.field_names, schema);
    _assert_fields('TTSStreamConfig', TTSStreamConfig.field_names, schema);
  });

  test('empty ASRStreamingConfig is all null and encodes as {}', () {
    const empty = ASRStreamingConfig();
    expect(empty.min_audio_s, isNull);
    expect(empty.algorithm, isNull);
    expect(empty.to_json(), isEmpty);
    expect(ASRStreamingConfig.field_names.length, 25);
  });

  test('policy defaults live on Swift, not Dart', () {
    final policy = schema['policy'] as Map;
    expect(policy['generic_min_audio_s'], 2.0);
    expect(policy['measured_word_times_min_audio_s'], 2.0);
    expect(policy['empty_streaming_config_means_pipeline_default'], isTrue);
    expect(const ASRStreamingConfig().to_json().containsKey('min_audio_s'),
        isFalse);
  });

  test('LLM sampling defaults are 0.7 / 20, TTS sampling stays null', () {
    final llm = LLMGenerationConfig();
    expect(llm.sampling.temperature, closeTo(0.7, 1e-6));
    expect(llm.sampling.top_k, 20);
    expect(const SamplingParams().temperature, closeTo(1.0, 1e-6));
    expect(const SamplingParams().top_k, 0);
    expect(const TTSGenerationConfig().sampling, isNull);
  });

  test('ASRResult maps metrics and generated_tokens', () {
    final result = ASRResult.from_json({
      'text': 'hi',
      'generated_tokens': 7,
      'decode_seconds': 0.2,
      'language': 'en',
      'metrics': {
        'generated_tokens': 7,
        'decode_seconds': 0.2,
        'rtf': 4.0,
      },
    });
    expect(result.generated_tokens, 7);
    expect(result.token_count, 7);
    expect(result.language, 'en');
    expect(result.metrics.generated_tokens, 7);
  });
}
