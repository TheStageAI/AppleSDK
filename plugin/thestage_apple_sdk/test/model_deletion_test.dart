import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';
import 'package:thestage_apple_sdk/src/method_channels.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(MethodChannels.main);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  void reply(Future<Object?> Function(MethodCall) handler) {
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('sends engines_path, leaves revision out when null', () async {
    reply((_) async => {
          'freed_bytes': 3630000000,
          'revisions': ['main', 'v1.6'],
        });
    final deleted = await TheStageFlutterSDK.delete_model(
      engines_path: 'TheStageAI/gemma-4',
    );
    expect(calls.single.method, 'delete_model');
    expect(calls.single.arguments, {'engines_path': 'TheStageAI/gemma-4'});
    expect(deleted.freed_bytes, 3630000000);
    expect(deleted.revisions, ['main', 'v1.6']);
  });

  test('passes one revision', () async {
    reply((_) async => {'freed_bytes': 0, 'revisions': <String>[]});
    final deleted = await TheStageFlutterSDK.delete_model(
      engines_path: 'TheStageAI/gemma-4',
      revision: 'v1.6',
    );
    expect(calls.single.arguments,
        {'engines_path': 'TheStageAI/gemma-4', 'revision': 'v1.6'});
    expect(deleted.freed_bytes, 0);
    expect(deleted.revisions, isEmpty);
  });

  test('model_in_use becomes ModelInUseException', () async {
    reply((_) async => throw PlatformException(
          code: 'THESTAGE_SDK_ERROR',
          message: 'loaded',
          details: {
            'reason': 'model_in_use',
            'engines_path': 'TheStageAI/gemma-4',
            'model_names': 'llm,summary',
            'message': 'TheStageAI/gemma-4 is loaded as llm, summary',
          },
        ));
    await expectLater(
      TheStageFlutterSDK.delete_model(engines_path: 'TheStageAI/gemma-4'),
      throwsA(isA<ModelInUseException>()
          .having((e) => e.model_names, 'model_names', ['llm', 'summary'])
          .having((e) => e.engines_path, 'engines_path', 'TheStageAI/gemma-4')),
    );
  });

  test('model_in_use with no handles has an empty list', () async {
    reply((_) async => throw PlatformException(
          code: 'THESTAGE_SDK_ERROR',
          details: {'reason': 'model_in_use', 'model_names': ''},
        ));
    await expectLater(
      TheStageFlutterSDK.delete_model(engines_path: 'x/y'),
      throwsA(isA<ModelInUseException>()
          .having((e) => e.model_names, 'model_names', isEmpty)),
    );
  });

  test('model_busy becomes ModelBusyException', () async {
    reply((_) async => throw PlatformException(
          code: 'THESTAGE_SDK_ERROR',
          details: {'reason': 'model_busy', 'engines_path': 'x/y'},
        ));
    await expectLater(
      TheStageFlutterSDK.delete_model(engines_path: 'x/y'),
      throwsA(isA<ModelBusyException>()),
    );
  });

  test('other failures stay PlatformException', () async {
    reply((_) async => throw PlatformException(
          code: 'THESTAGE_SDK_ERROR',
          details: {'classification': 'unknown', 'message': 'boom'},
        ));
    await expectLater(
      TheStageFlutterSDK.delete_model(engines_path: 'x/y'),
      throwsA(isA<PlatformException>()),
    );
  });
}
