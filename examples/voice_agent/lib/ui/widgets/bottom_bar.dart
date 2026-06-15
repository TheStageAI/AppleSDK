import 'package:flutter/material.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

import '../../backend/voice_agent_controller.dart';
import 'agent_status.dart';

// ============================================================================
// FRONTEND widget — bottom control bar
// ============================================================================
// Shows the current status line, a live mic-level meter (while listening), and
// the Start/Stop + Interrupt controls. All behaviour is delegated to the
// controller via [onToggleRun] and `controller.interrupt`.
// ============================================================================
class BottomBar extends StatelessWidget {
  const BottomBar({
    super.key,
    required this.controller,
    required this.onToggleRun,
  });

  final VoiceAgentController controller;
  final VoidCallback onToggleRun;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            agentStateLabel(controller),
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          if (controller.state == TheStageAgentState.listening) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: controller.vadLevel.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: controller.vadLevel > 0.5
                    ? Colors.green
                    : colorScheme.primary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: controller.state == TheStageAgentState.loading
                      ? null
                      : onToggleRun,
                  child: Text(controller.isRunning ? 'Stop' : 'Start'),
                ),
              ),
              if (controller.canInterrupt) ...[
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: controller.interrupt,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
                  ),
                  child: const Text('Interrupt'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
