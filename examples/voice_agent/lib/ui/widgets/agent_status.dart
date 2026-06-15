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
String agentStateLabel(VoiceAgentController c) {
  switch (c.state) {
    case TheStageAgentState.idle:
      return 'Idle';
    case TheStageAgentState.loading:
      if (c.currentLoadingModel == null) return 'Loading models...';
      return '${c.currentLoadingModel} - ${agentPhaseLabel(c)}';
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

/// Sub-status for the model currently loading (download → extract → compile).
String agentPhaseLabel(VoiceAgentController c) {
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
