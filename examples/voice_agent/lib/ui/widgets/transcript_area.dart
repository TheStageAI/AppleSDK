import 'package:flutter/material.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

import '../../backend/voice_agent_controller.dart';
import '../../models/chat_message.dart';
import 'agent_status.dart';
import 'chat_bubble.dart';

// ============================================================================
// FRONTEND widget — the conversation area
// ============================================================================
// Shows, in priority order:
//   1. the per-model loading checklist while models load,
//   2. a hint when there's nothing to show yet,
//   3. the chat transcript.
//
// The transcript draws, in conversation order:
//   • controller.messages          — finalized user + assistant lines
//   • controller.partialTranscript — the LIVE user bubble (streaming ASR)
//   • controller.streamingResponse — the LIVE assistant bubble (streaming LLM)
// The two live bubbles are appended after the finalized ones so the newest
// content is always at the bottom.
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
    final colorScheme = Theme.of(context).colorScheme;
    final hasContent = controller.messages.isNotEmpty ||
        controller.streamingResponse.isNotEmpty ||
        controller.partialTranscript.isNotEmpty;

    if (!hasContent) {
      if (controller.state == TheStageAgentState.loading) {
        return Center(child: LoadingChecklist(controller: controller));
      }
      return Center(
        child: Text(
          controller.isRunning ? 'Say something...' : 'Tap Start to begin',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    // Trailing LIVE bubbles, in conversation order: the user's streaming-ASR
    // partial (what you're saying now), then the assistant's streaming reply.
    final showPartial = controller.partialTranscript.isNotEmpty;
    final showStreaming = controller.streamingResponse.isNotEmpty;
    final extra = (showPartial ? 1 : 0) + (showStreaming ? 1 : 0);

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: controller.messages.length + extra,
      itemBuilder: (context, index) {
        // 1) Finalized lines first.
        if (index < controller.messages.length) {
          return MessageBubble(message: controller.messages[index]);
        }
        // 2) Then the live USER partial (if any).
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
        // 3) Then the live ASSISTANT stream.
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

// ============================================================================
// FRONTEND widget — startup model checklist
// ============================================================================
// Loaded models show a check; the one currently loading shows a spinner + its
// phase. Makes it obvious which model is loading and how far along it is.
// ============================================================================
class LoadingChecklist extends StatelessWidget {
  const LoadingChecklist({super.key, required this.controller});

  final VoiceAgentController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (controller.loadingModels.isEmpty) {
      return Text('Loading models...',
          style: TextStyle(color: colorScheme.onSurfaceVariant));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final model in controller.loadingModels)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (model == controller.currentLoadingModel)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                else
                  const Icon(Icons.check_circle, size: 18, color: Colors.green),
                const SizedBox(width: 10),
                Text(
                  model,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: model == controller.currentLoadingModel
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (model == controller.currentLoadingModel) ...[
                  const SizedBox(width: 8),
                  Text(
                    agentPhaseLabel(controller),
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
