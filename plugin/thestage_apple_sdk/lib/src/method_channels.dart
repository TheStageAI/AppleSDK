// ---------------------------------------------------------------------------
// MethodChannels
// ---------------------------------------------------------------------------
class MethodChannels {
  static const String main = 'thestage_apple_sdk';
  static const String progress = 'thestage_apple_sdk/progress';
  static const String ttsStream = 'thestage_apple_sdk/tts_stream';
  static const String voiceAgentEvents =
      'thestage_apple_sdk/voice_agent_events';
  static const String voiceAgentLLMDeltas =
      'thestage_apple_sdk/voice_agent_llm_deltas';
  static const String voiceAgentTranscripts =
      'thestage_apple_sdk/voice_agent_transcripts';
  static const String voiceAgentVADProbabilities =
      'thestage_apple_sdk/voice_agent_vad_probabilities';
}

// ---------------------------------------------------------------------------
// MethodRoute
// ---------------------------------------------------------------------------
class MethodRoute {
  static const String initialize = 'initialize';
  static const String startModel = 'start_model';
  static const String stopModel = 'stop_model';

  static const String listComponents = 'list_components';
  static const String loadComponents = 'load_components';
  static const String unloadComponents = 'unload_components';
  static const String bundledEnginePath = 'get_bundled_engine_path';

  static const String infer = 'infer';
  static const String startStream = 'start_stream';
  static const String send = 'send';
  static const String finishStream = 'finish_stream';
  static const String stopStream = 'stop_stream';

  static const String audioStart = 'audio_start';
  static const String audioEnqueue = 'audio_enqueue';
  static const String audioPause = 'audio_pause';
  static const String audioResume = 'audio_resume';
  static const String audioDrain = 'audio_drain';
  static const String audioStop = 'audio_stop';

  static const String voiceAgentStart = 'voice_agent.start';
  static const String voiceAgentStop = 'voice_agent.stop';
  static const String voiceAgentInterrupt = 'voice_agent.interrupt';
  static const String voiceAgentSay = 'voice_agent.say';
  static const String voiceAgentSetVoice = 'voice_agent.set_voice';
  static const String voiceAgentClearHistory =
      'voice_agent.clear_history';
  static const String voiceAgentUpdateInterruptConfig =
      'voice_agent.update_interrupt_config';
}
