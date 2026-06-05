import 'package:flutter/foundation.dart';

class VoiceAgentSettings extends ChangeNotifier {
  // Voice & Language
  String ttsVoice = 'paul';
  String sttLanguage = 'en';
  String systemPrompt =
      'You are a helpful voice assistant. Keep responses concise.';

  // LLM Provider (cloud only for now)
  String llmProvider = 'openai_compatible';
  String llmModel = 'gpt-4o-mini';
  String llmEndpoint = 'https://api.openai.com/v1/chat/completions';
  int maxTokens = 256;
  double temperature = 0.7;

  // Endpointing
  int silenceTimeoutMs = 600;
  double vadThreshold = 0.5;

  // Wake Word
  bool wakeWordEnabled = false;
  double wwThreshold = 0.7;
  int conversationTimeoutSec = 30;

  // Interruption
  bool allowInterruptions = true;
  String interruptMode = 'speech_only';
  int interruptMinSpeechMs = 300;

  // Audio
  int preRollMs = 200;
  bool aecEnabled = true;

  // Debug
  bool showMetrics = false;
  bool showPartialTranscript = true;
  bool speculativeWhisper = true;

  static const availableVoices = ['paul', 'bril', 'dave', 'jo'];
  static const availableLanguages = ['en', 'auto', 'fr', 'de', 'es'];

  Map<String, dynamic> toConfig(String apiKey) => {
        'vad': 'TheStageAI/silero-vad',
        'stt': 'TheStageAI/thewhisper-large-v3-turbo',
        'tts': 'TheStageAI/neutts-multilingual',
        'stt_revision': 'develop',
        'tts_revision': 'develop',
        'tts_voice': ttsVoice,
        'wake_word': wakeWordEnabled ? 'TheStageAI/wake-word' : null,
        'llm_provider': llmProvider,
        'llm_model': llmModel,
        'llm_endpoint': llmEndpoint,
        'llm_api_key': apiKey,
        'system_prompt': systemPrompt,
        'max_tokens': maxTokens,
        'temperature': temperature,
        'vad_threshold': vadThreshold,
        'silence_timeout_ms': silenceTimeoutMs,
        'allow_interruptions': allowInterruptions,
        'interrupt_mode': interruptMode,
        'interrupt_min_speech_ms': interruptMinSpeechMs,
        'pre_roll_ms': preRollMs,
        'aec_enabled': aecEnabled,
        'speculative_whisper': speculativeWhisper,
        'ww_threshold': wwThreshold,
        'conversation_timeout_sec': conversationTimeoutSec,
        'stt_language': sttLanguage,
      };

  void update(void Function(VoiceAgentSettings s) fn) {
    fn(this);
    notifyListeners();
  }
}
