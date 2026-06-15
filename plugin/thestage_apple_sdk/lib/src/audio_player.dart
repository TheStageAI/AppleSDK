import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'method_channels.dart';

// ---------------------------------------------------------------------------
// TheStageAudioPlayer
// ---------------------------------------------------------------------------
class TheStageAudioPlayer {
  static const MethodChannel _channel = MethodChannel(MethodChannels.main);
  static int _nextId = 0;

  final int sampleRate;
  final String _id;
  bool _playing = false;

  TheStageAudioPlayer({this.sampleRate = 24000})
      : _id = 'audio_${_nextId++}_${DateTime.now().microsecondsSinceEpoch}';

  bool get isPlaying => _playing;

  Future<void> start() async {
    await _channel.invokeMethod(MethodRoute.audioStart, {
      'player_id': _id,
      'sample_rate': sampleRate,
    });
    _playing = true;
  }

  void enqueue(Float32List audio) {
    if (!_playing) return;
    _channel.invokeMethod(MethodRoute.audioEnqueue, {
      'player_id': _id,
      'audio': audio,
    });
  }

  Future<void> pause() async {
    await _channel.invokeMethod(
      MethodRoute.audioPause,
      {'player_id': _id},
    );
  }

  Future<void> resume() async {
    await _channel.invokeMethod(
      MethodRoute.audioResume,
      {'player_id': _id},
    );
  }

  Future<void> drain() async {
    await _channel.invokeMethod(
      MethodRoute.audioDrain,
      {'player_id': _id},
    );
  }

  Future<void> stop() async {
    _playing = false;
    await _channel.invokeMethod(
      MethodRoute.audioStop,
      {'player_id': _id},
    );
  }
}
