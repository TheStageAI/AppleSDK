import 'package:flutter/services.dart';

import 'method_channels.dart';

/// In-app screen capture → Photos.
///
/// Keeps the live Voice Agent AEC / voiceChat session. Audio is a digital
/// mux of TTS + post-AEC mic (Control Center / ReplayKit cannot hear VPIO).
class TheStageScreenRecorder {
  TheStageScreenRecorder._();

  static const MethodChannel _channel = MethodChannel(MethodChannels.main);

  static Future<bool> isRecording() async {
    final v = await _channel.invokeMethod<bool>(
      MethodRoute.screenRecorderIsRecording,
    );
    return v ?? false;
  }

  static Future<void> start() =>
      _channel.invokeMethod<void>(MethodRoute.screenRecorderStart);

  static Future<void> stop() =>
      _channel.invokeMethod<void>(MethodRoute.screenRecorderStop);
}
