import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

import '../../backend/voice_agent_controller.dart';
import '../app_theme.dart';
import 'agent_status.dart';

// ============================================================================
// FRONTEND widget — frosted bottom control bar
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
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final running = controller.isRunning;
    final showMeter = controller.isStartupLoading ||
        controller.state == TheStageAgentState.listening;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF9F9F9))
                .withValues(alpha: 0.82),
            border: Border(
              top: BorderSide(
                color: scheme.outline.withValues(alpha: 0.35),
                width: 0.33,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    agentStateLabel(controller),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.08,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (showMeter) ...[
                    const SizedBox(height: 10),
                    _Meter(
                      value: controller.isStartupLoading
                          ? agentLoadProgressValue(controller)
                          : controller.vadLevel.clamp(0.0, 1.0),
                      color: controller.isStartupLoading
                          ? scheme.primary
                          : (controller.vadLevel > 0.45
                              ? AppColors.systemGreen
                              : scheme.primary),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed:
                              controller.state == TheStageAgentState.loading
                                  ? null
                                  : onToggleRun,
                          style: FilledButton.styleFrom(
                            backgroundColor: running
                                ? AppColors.systemRed
                                : scheme.primary,
                            disabledBackgroundColor:
                                scheme.primary.withValues(alpha: 0.35),
                            minimumSize: const Size.fromHeight(52),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                running
                                    ? Icons.stop_rounded
                                    : Icons.play_arrow_rounded,
                                size: 22,
                              ),
                              const SizedBox(width: 6),
                              Text(running ? 'Stop' : 'Start'),
                            ],
                          ),
                        ),
                      ),
                      if (controller.canInterrupt) ...[
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 52,
                          child: FilledButton.tonal(
                            onPressed: controller.interrupt,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.systemOrange
                                  .withValues(alpha: isDark ? 0.22 : 0.14),
                              foregroundColor: isDark
                                  ? const Color(0xFFFFB340)
                                  : const Color(0xFFC93400),
                              shape: const StadiumBorder(),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.front_hand_rounded, size: 18),
                                SizedBox(width: 6),
                                Text('Interrupt'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.value, required this.color});

  final double? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(100),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 3.5,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        color: color,
      ),
    );
  }
}
