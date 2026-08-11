import 'package:flutter/material.dart';

import '../app_theme.dart';

// ============================================================================
// FRONTEND widget — dismissible error banner
// ============================================================================
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg =
        isDark ? const Color(0xFFFFB4A8) : const Color(0xFF9B1B1B);
    return Material(
      color: AppColors.systemRed.withValues(alpha: isDark ? 0.22 : 0.10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.error_rounded, size: 18, color: fg),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: fg,
                  fontSize: 14,
                  height: 1.3,
                  letterSpacing: -0.1,
                ),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 18, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}
