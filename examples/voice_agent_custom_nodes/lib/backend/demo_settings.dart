import 'package:flutter/foundation.dart';

/// Tunables for the custom-nodes demo (flattened into agent start config).
class DemoSettings extends ChangeNotifier {
  static const hfVad = 'TheStageAI/silero-vad';
  static const hfStt = 'TheStageAI/thewhisper-large-v3-turbo';
  static const hfTts = 'TheStageAI/Qwen3-TTS-12Hz-0.6B-Base';
  static const hfLlm = 'TheStageAI/LFM2.5-350M';
  static const hfVlm = 'TheStageAI/LFM2.5-VL-450M';
  static const hfAec = 'TheStageAI/dtln-aec';

  String vad = hfVad;
  String stt = hfStt;
  String tts = hfTts;
  String llm = hfLlm;
  String vlm = hfVlm;
  String aecEnginesPath = hfAec;

  int sampleRateOut = 24000;
  String aecMethod = 'vpio'; // vpio | neural | none

  String ttsVoice = 'paul';
  String systemPrompt =
      'You are a concise on-device voice assistant. Keep replies short.';

  Map<String, dynamic> toAgentConfig() => {
        'vad': vad,
        'stt': stt,
        'tts': tts,
        'tts_voice': ttsVoice,
        'llm_provider': 'local',
        'llm_model': 'llm',
        'system_prompt': systemPrompt,
        'auto_listen': false,
        'sample_rate_in': 16000,
        'sample_rate_out': sampleRateOut,
        'tts_sample_rate': 24000,
        'aec_method': aecMethod,
        'aec_engines_path': aecEnginesPath,
        'turn_end_mode': 'vad',
        'interrupt_mode': aecMethod == 'none' ? 'none' : 'vad',
      };

  void setSampleRateOut(int hz) {
    sampleRateOut = hz;
    notifyListeners();
  }

  void setAecMethod(String method) {
    aecMethod = method;
    notifyListeners();
  }
}
