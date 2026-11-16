import 'package:flutter_test/flutter_test.dart';
import 'package:thestage_apple_sdk/src/asr_engine.dart';
import 'package:thestage_apple_sdk/src/asr_stream.dart';

void main() {
  test('empty streaming config stays optional on the wire', () {
    expect(const ASRStreamingConfig().to_json(), isEmpty);
    expect(
      ASRStreamingAlgorithm.values,
      contains(ASRStreamingAlgorithm.NAIVE),
    );
    expect(
      ASRStreamingAlgorithm.values,
      contains(ASRStreamingAlgorithm.THESTAGE_V5),
    );
  });

  test('prefix control is explicit on the wire', () {
    expect(
      const ASRStreamingConfig(
        algorithm: ASRStreamingAlgorithm.NAIVE,
        use_prefix: true,
      ).to_json(),
      {
        'algorithm': 'NAIVE',
        'use_prefix': true,
      },
    );
  });

  test('V6 cut settings reach native JSON without changing empty defaults', () {
    expect(
      const ASRStreamingConfig(
        algorithm: ASRStreamingAlgorithm.THESTAGE_V6,
        cut_search_s: 6,
        cut_force_s: 9.5,
        cut_age_s: 1,
        cut_confirm_ratio: 0.8,
        cut_veto_cer: 0.2,
        cut_pick: 'last',
        clock_release_s: 8,
      ).to_json(),
      {
        'algorithm': 'THESTAGE_V6',
        'cut_search_s': 6,
        'cut_force_s': 9.5,
        'cut_age_s': 1,
        'cut_confirm_ratio': 0.8,
        'cut_veto_cer': 0.2,
        'cut_pick': 'last',
        'clock_release_s': 8,
      },
    );
  });

  test('consecutive local agreement is explicit on the wire', () {
    expect(
      const ASRStreamingConfig(
        n_confirmations: 3,
        agreement_mode: ASRLocalAgreementMode.CONSECUTIVE,
      ).to_json(),
      {
        'n_confirmations': 3,
        'agreement_mode': 'CONSECUTIVE',
      },
    );
  });

  test('ASREngine holds optional vad handle', () {
    expect(ASREngine(stt: 'stt', vad: 'vad').vad, 'vad');
    expect(ASREngine(stt: 'stt').vad, isNull);
  });

  test('ASRStreamEvent parses begin / turn / termination', () {
    expect(ASRStreamEvent.from_json({'kind': 'BEGIN'}).is_begin, isTrue);
    expect(
      ASRStreamEvent.from_json({'kind': 'turn', 'transcript': 'hi'}).is_turn,
      isTrue,
    );
    expect(
      ASRStreamEvent.from_json({'kind': 'termination'}).is_termination,
      isTrue,
    );
  });
}
