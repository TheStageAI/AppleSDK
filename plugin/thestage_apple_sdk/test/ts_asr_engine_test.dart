import 'package:flutter_test/flutter_test.dart';
import 'package:thestage_apple_sdk/src/method_channels.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

void main() {
  group('TSASRTurn', () {
    test('maps the field set the native side emits', () {
      final turn = TSASRTurn.from_json(const {
        'transcript': 'hello there',
        'committed': 'hello',
        'hypothesis': 'there',
        'end_of_turn': false,
        'is_final': false,
      });

      expect(turn.transcript, 'hello there');
      expect(turn.committed, 'hello');
      expect(turn.hypothesis, 'there');
      expect(turn.end_of_turn, isFalse);
    });

    test('missing keys degrade to empty rather than throwing', () {
      final turn = TSASRTurn.from_json(const {});

      expect(turn.transcript, '');
      expect(turn.committed, '');
      expect(turn.hypothesis, '');
      expect(turn.end_of_turn, isFalse);
    });

    test('end_of_turn is only true for an explicit true', () {
      expect(TSASRTurn.from_json(const {'end_of_turn': true}).end_of_turn,
          isTrue);
      // A null or a stray string must not read as a finished turn: the UI
      // uses this to decide when to stop rewriting a line.
      expect(TSASRTurn.from_json(const {'end_of_turn': 'yes'}).end_of_turn,
          isFalse);
    });

    group('display', () {
      test('joins committed and hypothesis for a live caption', () {
        const turn = TSASRTurn(committed: 'hello', hypothesis: 'there');
        expect(turn.display, 'hello there');
      });

      test('does not leave a leading space before the first words', () {
        const turn = TSASRTurn(committed: '', hypothesis: 'hello');
        expect(turn.display, 'hello');
      });

      test('does not leave a trailing space once the tail is committed', () {
        const turn = TSASRTurn(committed: 'hello there', hypothesis: '');
        expect(turn.display, 'hello there');
      });
    });
  });

  group('TSASREngine', () {
    test('is_running is false before start', () {
      expect(TSASREngine().is_running, isFalse);
    });

    test('channel names match the native MethodChannels', () {
      // These strings are the wire contract with
      // ios/.../internal/MethodChannels.swift. A rename on one side only is
      // a silent no-events bug, so pin them here.
      expect(MethodChannels.asrEngineTurns,
          'thestage_apple_sdk/asr_engine_turns');
      expect(MethodChannels.asrEngineTranscripts,
          'thestage_apple_sdk/asr_engine_transcripts');
      expect(MethodChannels.asrEnginePartials,
          'thestage_apple_sdk/asr_engine_partials');
      expect(MethodChannels.asrEngineVADProbabilities,
          'thestage_apple_sdk/asr_engine_vad_probabilities');
      expect(MethodChannels.asrEngineEvents,
          'thestage_apple_sdk/asr_engine_events');
      expect(MethodRoute.asrEngineStart, 'asr_engine.start');
      expect(MethodRoute.asrEngineStop, 'asr_engine.stop');
    });
  });

  group('TS* compatibility aliases', () {
    test('the old Dart names still resolve to the renamed classes', () {
      // ignore: deprecated_member_use_from_same_package
      expect(TheStageAgentState.listening, TSAgentState.listening);
    });
  });
}
