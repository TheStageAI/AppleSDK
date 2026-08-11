import 'package:flutter_test/flutter_test.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';
import 'package:voice_agent_custom_nodes/nodes/event_log_node.dart';

void main() {
  test('EventLogNode onEvent forwards bus maps', () async {
    final seen = <Map<String, dynamic>>[];
    final node = EventLogNode(onBusEvent: seen.add);
    final ctx = AgentNodeContext(
      nodeId: 'event_log',
      state: 'idle',
      isGateOpen: true,
      sendPort: (_, __) {},
      publishEvent: (_) {},
      portEvents: const Stream.empty(),
    );
    await node.onEvent(ctx, {'kind': 'USER_REQUEST', 'text': 'hi'});
    expect(seen, hasLength(1));
    expect(seen.first['kind'], 'USER_REQUEST');
  });
}
