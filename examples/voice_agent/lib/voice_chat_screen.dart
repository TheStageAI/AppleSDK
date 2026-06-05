import 'package:flutter/material.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

import 'settings_model.dart';
import 'settings_screen.dart';
import 'voice_agent_controller.dart';

/// The main voice-chat screen.
///
/// All of the agent's behaviour (transcription, LLM streaming, model loading)
/// lives in [VoiceAgentController]. This widget is intentionally "dumb": it
/// only renders the controller's fields and wires the buttons. The layout is:
///
///   AppBar .................. title + settings + status dot
///   _ErrorBanner ............ shown only when controller.error != null
///   _TranscriptArea ......... loading checklist / hint / chat bubbles
///   _BottomBar .............. status line, mic level, Start/Stop/Interrupt
class VoiceChatScreen extends StatefulWidget {
  const VoiceChatScreen({
    super.key,
    required this.agent,
    required this.settings,
    required this.openAIKey,
  });

  final TheStageVoiceAgentFlutter agent;
  final VoiceAgentSettings settings;
  final String openAIKey;

  @override
  State<VoiceChatScreen> createState() => _VoiceChatScreenState();
}

class _VoiceChatScreenState extends State<VoiceChatScreen> {
  late final VoiceAgentController _controller =
      VoiceAgentController(widget.agent);
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Auto-scroll the transcript whenever the controller emits new content.
    _controller.addListener(_scrollToBottom);
  }

  @override
  void dispose() {
    _controller.removeListener(_scrollToBottom);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleRun() {
    if (_controller.isRunning) {
      _controller.stop();
    } else {
      _controller.start(widget.settings.toConfig(widget.openAIKey));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Agent'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(
                  settings: widget.settings,
                  agent: widget.agent,
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Icon(Icons.circle,
                  size: 14, color: _stateColor(_controller.state)),
            ),
          ),
        ],
      ),
      // One listener for the whole screen: rebuild when controller changes.
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Column(
            children: [
              if (_controller.error != null)
                _ErrorBanner(
                  message: _controller.error!,
                  onDismiss: _controller.clearError,
                ),
              Expanded(
                child: _TranscriptArea(
                  controller: _controller,
                  scrollController: _scrollController,
                ),
              ),
              _BottomBar(controller: _controller, onToggleRun: _toggleRun),
            ],
          );
        },
      ),
    );
  }
}

/// The conversation area. Shows, in priority order:
///   1. the per-model loading checklist while models load,
///   2. a hint when there's nothing to show yet,
///   3. the chat transcript (user + assistant bubbles, streaming last).
class _TranscriptArea extends StatelessWidget {
  const _TranscriptArea({
    required this.controller,
    required this.scrollController,
  });

  final VoiceAgentController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasContent = controller.messages.isNotEmpty ||
        controller.streamingResponse.isNotEmpty;

    if (!hasContent) {
      if (controller.state == TheStageAgentState.loading) {
        return Center(child: _LoadingChecklist(controller: controller));
      }
      return Center(
        child: Text(
          controller.isRunning ? 'Say something...' : 'Tap Start to begin',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    // The streaming reply (if any) is rendered as one extra bubble at the end.
    final showStreaming = controller.streamingResponse.isNotEmpty;
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: controller.messages.length + (showStreaming ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < controller.messages.length) {
          return _MessageBubble(message: controller.messages[index]);
        }
        return _MessageBubble(
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

/// Per-model startup checklist: loaded models show a check, the one currently
/// loading shows a spinner + its phase. Makes it obvious which is loading.
class _LoadingChecklist extends StatelessWidget {
  const _LoadingChecklist({required this.controller});

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
                    _phaseLabel(controller),
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

/// Bottom bar: current status line, live mic level (while listening), and the
/// Start/Stop + Interrupt controls.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.controller, required this.onToggleRun});

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
            _stateLabel(controller),
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

/// Dismissible red banner shown when the controller reports an error.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

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

/// A single chat bubble. User turns align right; assistant/error align left.
/// While the assistant is still streaming, a small spinner is shown.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, this.isStreaming = false});

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
                child: CircularProgressIndicator(strokeWidth: 2, color: fgColor),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// -- Presentation helpers ------------------------------------------------

/// Colour of the status dot for the current agent state.
Color _stateColor(TheStageAgentState state) {
  switch (state) {
    case TheStageAgentState.idle:
      return Colors.grey;
    case TheStageAgentState.loading:
      return Colors.amber;
    case TheStageAgentState.sleeping:
      return Colors.blueGrey;
    case TheStageAgentState.listening:
      return Colors.green;
    case TheStageAgentState.thinking:
      return Colors.purple;
    case TheStageAgentState.speaking:
      return Colors.blue;
  }
}

/// Human-readable status line shown in the bottom bar.
String _stateLabel(VoiceAgentController c) {
  switch (c.state) {
    case TheStageAgentState.idle:
      return 'Idle';
    case TheStageAgentState.loading:
      if (c.currentLoadingModel == null) return 'Loading models...';
      return '${c.currentLoadingModel} - ${_phaseLabel(c)}';
    case TheStageAgentState.sleeping:
      return 'Waiting for wake word...';
    case TheStageAgentState.listening:
      return 'Listening...';
    case TheStageAgentState.thinking:
      return 'Thinking...';
    case TheStageAgentState.speaking:
      return 'Speaking...';
  }
}

/// Sub-status for the model currently loading (download -> extract -> compile).
String _phaseLabel(VoiceAgentController c) {
  switch (c.loadPhase) {
    case 'downloading':
      return 'downloading ${(c.downloadProgress * 100).toStringAsFixed(0)}%';
    case 'extracting':
      return 'extracting...';
    case 'loading':
      return 'loading & compiling...';
    default:
      return 'preparing...';
  }
}
