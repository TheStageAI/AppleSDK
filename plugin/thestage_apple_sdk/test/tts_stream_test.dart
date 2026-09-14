import 'package:flutter_test/flutter_test.dart';
import 'package:thestage_apple_sdk/src/inference_types.dart';
import 'package:thestage_apple_sdk/src/tts_stream.dart';

void main() {
  test('TTSGenerationConfig empty sampling stays null', () {
    expect(const TTSGenerationConfig().sampling, isNull);
    expect(const TTSGenerationConfig().to_json()['sampling'], isNull);
  });

  test('TTSStream exposes the five verbs', () {
    expect(TTSStream.open, isA<Function>());
  });
}
