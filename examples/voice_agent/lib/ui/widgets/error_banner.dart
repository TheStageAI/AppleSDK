import 'package:flutter/material.dart';

// ============================================================================
// FRONTEND widget — dismissible error banner
// ============================================================================
// Shown at the top of the screen only while `controller.error != null`.
// Tapping the close icon calls [onDismiss] (controller.clearError).
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: Colors.red.shade100,
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.red.shade900, fontSize: 13),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close, size: 18, color: Colors.red.shade900),
          ),
        ],
      ),
    );
  }
}
