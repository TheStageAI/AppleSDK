import 'package:flutter/material.dart';

import '../../backend/voice_agent_controller.dart';
import '../../models/chat_message.dart';
import '../app_theme.dart';
import 'agent_status.dart';
import 'chat_bubble.dart';

// ============================================================================
// FRONTEND widget — the conversation area
// ============================================================================
class TranscriptArea extends StatelessWidget {
  const TranscriptArea({
    super.key,
    required this.controller,
    required this.scrollController,
  });

  final VoiceAgentController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasContent = controller.messages.isNotEmpty ||
        controller.streamingResponse.isNotEmpty ||
        controller.partialTranscript.isNotEmpty;

    if (!hasContent) {
      if (controller.isStartupLoading) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: LoadingChecklist(controller: controller),
          ),
        );
      }
      return _EmptyState(
        running: controller.isRunning,
        color: scheme.onSurfaceVariant,
      );
    }

    final showPartial = controller.partialTranscript.isNotEmpty;
    final showStreaming = controller.streamingResponse.isNotEmpty;
    final extra = (showPartial ? 1 : 0) + (showStreaming ? 1 : 0);

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: controller.messages.length + extra,
      itemBuilder: (context, index) {
        if (index < controller.messages.length) {
          return MessageBubble(message: controller.messages[index]);
        }
        var tail = index - controller.messages.length;
        if (showPartial) {
          if (tail == 0) {
            return MessageBubble(
              message: ChatMessage(
                role: MessageRole.user,
                text: controller.partialTranscript,
              ),
              isStreaming: true,
            );
          }
          tail -= 1;
        }
        return MessageBubble(
          message: ChatMessage(
            role: MessageRole.assistant,
            text: controller.streamingResponse,
          ),
          isStreaming: true,
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.running, required this.color});

  final bool running;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.18),
                    Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.06),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                running ? Icons.mic_rounded : Icons.graphic_eq_rounded,
                size: 34,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              running ? 'Listening' : 'Ready when you are',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
                height: 1.1,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              running
                  ? 'Say something — your transcript will appear here.'
                  : 'Choose models below, then tap Start.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                height: 1.35,
                letterSpacing: -0.2,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// FRONTEND widget — startup model checklist
// ============================================================================
class LoadingChecklist extends StatelessWidget {
  const LoadingChecklist({super.key, required this.controller});

  final VoiceAgentController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (controller.loadingModels.isEmpty) {
      return Text(
        'Loading models…',
        style: TextStyle(color: scheme.onSurfaceVariant),
      );
    }

    String shortName(String id) {
      final slash = id.lastIndexOf('/');
      return slash >= 0 ? id.substring(slash + 1) : id;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Preparing on-device stack',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Downloading and loading models',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            for (final model in controller.loadingModels)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (model == controller.currentLoadingModel)
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.primary,
                            ),
                          )
                        else
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: AppColors.systemGreen,
                          ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            shortName(model),
                            style: TextStyle(
                              fontSize: 15,
                              letterSpacing: -0.2,
                              fontWeight:
                                  model == controller.currentLoadingModel
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        if (model == controller.currentLoadingModel)
                          Text(
                            agentPhaseLabel(controller),
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    if (model == controller.currentLoadingModel) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(100),
                        child: LinearProgressIndicator(
                          value: agentLoadProgressValue(controller),
                          minHeight: 4,
                          backgroundColor: scheme.surfaceContainerHighest,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
