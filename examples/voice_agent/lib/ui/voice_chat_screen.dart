import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

import '../backend/settings_model.dart';
import '../backend/voice_agent_controller.dart';
import 'settings_screen.dart';
import 'widgets/agent_status.dart';
import 'widgets/bottom_bar.dart';
import 'widgets/error_banner.dart';
import 'widgets/model_picker_bar.dart';
import 'widgets/transcript_area.dart';

// ============================================================================
// FRONTEND — top-level screen (pure composition)
// ============================================================================
// This widget owns the [VoiceAgentController] (the backend bridge) and wires
// the pieces together. It holds NO conversation logic itself — it only:
//   • creates / disposes the controller,
//   • rebuilds the tree when the controller notifies (one AnimatedBuilder),
//   • routes button taps to controller commands,
//   • builds the start config and stages the bundled turn-detector asset.
//
// Layout:
//   AppBar ............. title + settings + status dot
//   ErrorBanner ........ only when controller.error != null
//   TranscriptArea ..... loading checklist / hint / chat bubbles
//   ModelPickerBar ..... LLM / ASR / TTS / voice (idle; before Start)
//   BottomBar .......... status line, mic level, Start/Stop/Interrupt
// ============================================================================
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
    widget.settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    _controller.removeListener(_scrollToBottom);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
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

  Future<void> _toggleRun() async {
    if (_controller.isRunning) {
      await _controller.stop();
      await widget.settings.stopLocalLlm();
      return;
    }
    try {
      // Don't seed the checklist with STT — that made Whisper appear twice
      // (fake row, then real `STT (...)` from the agent). Keep the loader
      // held so deferred LFM still shows after agent.start.
      final local = widget.settings.useLocalBundles;
      final deferLlm = widget.settings.llmProvider == 'local';
      _controller.beginStartup(holdForDeferredLlm: deferLlm);
      var config = widget.settings.toConfig(widget.openAIKey);
      if (local) {
        config = await widget.settings.resolveLocalConfig(config);
      }
      await _controller.start(config);
      if (deferLlm) {
        // Models are up but mic is still closed (`auto_listen: false`).
        // Load LLM next (HF or bundled), then arm listening.
        final label = local
            ? widget.settings.localLlmBundle
            : widget.settings.llmModel;
        _controller.beginDeferredModel(label);
        await widget.settings.startLocalLlm();
        await _controller.beginListening();
        _controller.finishDeferredLoad();
      }
    } catch (e) {
      _controller.failStartup(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        title: Column(
          children: [
            const Text('Voice Agent'),
            Text(
              'TheStage',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final color = agentStateColor(_controller.state);
              return Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.5),
                          blurRadius: 5,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined, size: 22),
            onPressed: () => Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => SettingsScreen(
                  settings: widget.settings,
                  agent: widget.agent,
                ),
              ),
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Column(
            children: [
              if (_controller.error != null)
                ErrorBanner(
                  message: _controller.error!,
                  onDismiss: _controller.clearError,
                ),
              Expanded(
                child: TranscriptArea(
                  controller: _controller,
                  scrollController: _scrollController,
                ),
              ),
              ModelPickerBar(
                settings: widget.settings,
                enabled: !_controller.isRunning &&
                    !_controller.isStartupLoading,
              ),
              BottomBar(controller: _controller, onToggleRun: _toggleRun),
            ],
          );
        },
      ),
    );
  }
}
