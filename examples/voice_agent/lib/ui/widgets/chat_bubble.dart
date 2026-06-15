import 'package:flutter/material.dart';

import '../../models/chat_message.dart';

// ============================================================================
// FRONTEND widget — one chat bubble
// ============================================================================
// Dumb: given a [ChatMessage], draw it. User turns align right (primary
// colour), assistant/error align left. A small spinner shows while the line is
// still streaming (a live ASR partial or a mid-stream LLM reply).
// ============================================================================
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
  });

  final ChatMessage message;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUser = message.role == MessageRole.user;
    final isError = message.role == MessageRole.error;

    final Color bgColor;
    final Color fgColor;
    if (isError) {
      bgColor = colorScheme.error;
      fgColor = colorScheme.onError;
    } else if (isUser) {
      bgColor = colorScheme.primary;
      fgColor = colorScheme.onPrimary;
    } else {
      bgColor = colorScheme.tertiary;
      fgColor = colorScheme.onTertiary;
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                message.text,
                style: TextStyle(color: fgColor, fontSize: 15),
              ),
            ),
            if (isStreaming) ...[
              const SizedBox(width: 6),
              SizedBox(
                width: 12,
                height: 12,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: fgColor),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
