import 'package:flutter_test/flutter_test.dart';
import 'package:thestage_apple_sdk/src/model_component.dart';

void main() {
  test('ModelComponentStatus.from_json prefers state', () {
    final status = ModelComponentStatus.from_json({
      'id': 'talker',
      'kind': 'llm',
      'state': 'OFFLOADED',
      'loaded': true,
      'can_offload': true,
      'active_leases': 0,
    });
    expect(status.id, 'talker');
    expect(status.state, ModelComponentState.OFFLOADED);
    expect(status.loaded, isFalse);
  });

  test('legacy loaded bool still maps', () {
    final status = ModelComponentStatus.from_json({
      'id': 'codec',
      'kind': 'codec',
      'loaded': true,
      'can_offload': true,
    });
    expect(status.state, ModelComponentState.LOADED);
  });
}
