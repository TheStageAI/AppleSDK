// ============================================================================
// MODEL layer
// ============================================================================
// Plain data the UI draws. No Flutter, no SDK — just the shape of a transcript
// line. Lives between the backend (which produces these from SDK events) and
// the frontend (which renders them as bubbles).
// ============================================================================

/// Who authored a transcript line.
///
///   [user]      — produced by speech recognition (ASR): what *you* said.
///   [assistant] — produced by the LLM: what the agent replied.
///   [error]     — a surfaced error, shown inline in the transcript.
enum MessageRole { user, assistant, error }

/// One finalized line in the conversation transcript.
///
/// The UI renders a [user] line as a right-aligned bubble and an [assistant]
/// line as a left-aligned bubble (see `ui/widgets/chat_bubble.dart`).
class ChatMessage {
  ChatMessage({required this.role, required this.text});

  final MessageRole role;

  /// The line's text. Mutable so a streaming assistant reply can grow in place
  /// if a caller chooses to (the controller currently appends a fresh message
  /// on finalize instead, but the field stays mutable for flexibility).
  String text;
}
