import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../app_theme.dart';

// ============================================================================
// FRONTEND widget — one chat bubble (iMessage-style)
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = message.role == MessageRole.user;
    final isError = message.role == MessageRole.error;
    final isTool = message.role == MessageRole.tool;

    final Color bgColor;
    final Color fgColor;
    if (isError) {
      bgColor = AppColors.systemRed.withValues(alpha: isDark ? 0.28 : 0.12);
      fgColor = isDark ? const Color(0xFFFF8A80) : const Color(0xFFB00020);
    } else if (isTool) {
      bgColor = isDark
          ? const Color(0xFF1E2A24)
          : const Color(0xFFE8F2EC);
      fgColor = isDark
          ? const Color(0xFF9AD4B0)
          : const Color(0xFF1B5E3B);
    } else if (isUser) {
      bgColor = Theme.of(context).colorScheme.primary;
      fgColor = Colors.white;
    } else {
      bgColor =
          isDark ? AppColors.bubbleGrayDark : AppColors.bubbleGrayLight;
      fgColor = Theme.of(context).colorScheme.onSurface;
    }

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(isUser ? 20 : 6),
      bottomRight: Radius.circular(isUser ? 6 : 20),
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        margin: EdgeInsets.only(
          top: 3,
          bottom: 3,
          left: isUser ? 56 : 16,
          right: isUser ? 16 : 56,
        ),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: radius,
          border: isTool
              ? Border.all(
                  color: fgColor.withValues(alpha: 0.35),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                message.text,
                style: TextStyle(
                  color: fgColor,
                  fontSize: isTool ? 12.5 : 16,
                  height: 1.28,
                  letterSpacing: -0.2,
                  fontFamily: isTool ? 'Menlo' : null,
                  fontFamilyFallback:
                      isTool ? const ['Courier', 'monospace'] : null,
                ),
              ),
            ),
            if (isStreaming) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: fgColor.withValues(alpha: 0.85),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
