import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

/// Teaching example: listen to the internal agent bus via [onEvent].
class EventLogNode extends TheStageAgentNode {
  EventLogNode({
    this.id = 'event_log',
    this.onBusEvent,
  });

  @override
  final String id;

  @override
  final List<String> runWhen = const [];

  final void Function(Map<String, dynamic> event)? onBusEvent;

  @override
  Future<void> onEvent(
    AgentNodeContext context,
    Map<String, dynamic> event,
  ) async {
    onBusEvent?.call(event);
  }
}
