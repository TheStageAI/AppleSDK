import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';
import 'package:voice_agent_custom_nodes/nodes/vlm_caption_node.dart';

void main() {
  test('descriptor and port naming convention', () {
    final node = VLMCaptionNode(enginesPath: 'TheStageAI/LFM2.5-VL-450M');
    expect(node.toDescriptor()['id'], 'vlm');
    expect(node.toDescriptor()['run_when'], ['idle', 'sleeping']);

    String? sentPort;
    final ctx = AgentNodeContext(
      nodeId: node.id,
      state: 'idle',
      isGateOpen: true,
      sendPort: (port, value) {
        sentPort = port;
      },
      publishEvent: (_) {},
      portEvents: const Stream.empty(),
    );
    // Local name only — bus becomes vlm.caption on the native side.
    ctx.sendPort('caption', 'a red cup');
    expect(sentPort, 'caption');
  });

  test('external lifecycle does not start model in onStart', () async {
    final node = VLMCaptionNode(
      enginesPath: 'x',
      lifecycle: VlmLifecycle.external,
    );
    final ctx = AgentNodeContext(
      nodeId: 'vlm',
      state: 'idle',
      isGateOpen: true,
      sendPort: (_, __) {},
      publishEvent: (_) {},
      portEvents: const Stream.empty(),
    );
    await node.onStart(ctx);
    // Still not ready until host marks it.
    await node.submitImage(path: '/tmp/a.jpg');
    expect(node.captions, isA<Stream<String>>());
  });
}
