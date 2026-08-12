import 'package:flutter/material.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

import '../../backend/voice_agent_controller.dart';

// ============================================================================
// FRONTEND helpers — map agent state to presentation (colour + labels)
// ============================================================================
// Pure functions: agent state in, display value out. No widget state.
// ============================================================================

/// Colour of the status dot in the app bar for the current agent state.
Color agentStateColor(TheStageAgentState state) {
  switch (state) {
    case TheStageAgentState.idle:
      return const Color(0xFF8E8E93); // systemGray
    case TheStageAgentState.loading:
      return const Color(0xFFFF9500); // systemOrange
    case TheStageAgentState.sleeping:
      return const Color(0xFF636366);
    case TheStageAgentState.listening:
      return const Color(0xFF34C759); // systemGreen
    case TheStageAgentState.thinking:
      return const Color(0xFF007AFF); // systemBlue
    case TheStageAgentState.tool_calling:
      return const Color(0xFF5856D6); // systemIndigo
    case TheStageAgentState.speaking:
      return const Color(0xFF0A84FF);
  }
}

/// Human-readable status line shown in the bottom bar.
String agentStateLabel(VoiceAgentController c) {
  if (c.isStartupLoading) {
    if (c.currentLoadingModel == null) return 'Loading models…';
    return '${_shortModelName(c.currentLoadingModel!)} — ${agentPhaseLabel(c)}';
  }
  switch (c.state) {
    case TheStageAgentState.idle:
      return 'Idle';
    case TheStageAgentState.loading:
      if (c.currentLoadingModel == null) return 'Loading models…';
      return '${_shortModelName(c.currentLoadingModel!)} — ${agentPhaseLabel(c)}';
    case TheStageAgentState.sleeping:
      return 'Waiting for wake word…';
    case TheStageAgentState.listening:
      return 'Listening…';
    case TheStageAgentState.thinking:
      return 'Thinking…';
    case TheStageAgentState.tool_calling:
      return 'Calling tool…';
    case TheStageAgentState.speaking:
      return 'Speaking…';
  }
}

/// Friendly sub-status for the model currently loading (no internal jargon).
String agentPhaseLabel(VoiceAgentController c) {
  switch (c.loadPhase) {
    case 'downloading':
      final pct = (c.downloadProgress * 100).clamp(0, 100).toStringAsFixed(0);
      return 'Downloading $pct%';
    case 'extracting':
      return 'Extracting…';
    case 'loading':
      return 'Compiling…';
    case 'ready':
      return 'Ready';
    default:
      return 'Preparing…';
  }
}

/// Determinate progress while downloading; `null` = indeterminate bar.
///
/// Download maps to 0–70% of the bar; extract/compile leave the bar
/// indeterminate so we never look "stuck at 70%" during CoreML compile.
double? agentLoadProgressValue(VoiceAgentController c) {
  if (!c.isStartupLoading && c.state != TheStageAgentState.loading) {
    return null;
  }
  if (c.loadPhase == 'downloading' && c.downloadProgress > 0) {
    return c.downloadProgress.clamp(0.0, 1.0);
  }
  // Extract / compile — no useful byte fraction; animate.
  return null;
}

String _shortModelName(String id) {
  final slash = id.lastIndexOf('/');
  return slash >= 0 ? id.substring(slash + 1) : id;
}
