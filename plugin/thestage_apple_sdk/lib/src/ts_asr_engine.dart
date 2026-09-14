import 'dart:async';

import 'package:flutter/services.dart';

import 'method_channels.dart';

// ---------------------------------------------------------------------------
// TSASRTurn
// ---------------------------------------------------------------------------
/// One decoder turn. `committed` is text the commit ladder has accepted and
/// will not rewrite; `hypothesis` is the rewriteable tail. Render committed
/// text solid and the hypothesis dimmed — that is the whole point of having
/// both.
class TSASRTurn {
  final String transcript;
  final String committed;
  final String hypothesis;
  final bool end_of_turn;

  const TSASRTurn({
    this.transcript = '',
    this.committed = '',
    this.hypothesis = '',
    this.end_of_turn = false,
  });

  factory TSASRTurn.from_json(Map<String, dynamic> json) => TSASRTurn(
        transcript: json['transcript'] as String? ?? '',
        committed: json['committed'] as String? ?? '',
        hypothesis: json['hypothesis'] as String? ?? '',
        end_of_turn: json['end_of_turn'] == true,
      );

  /// What a caption should show right now.
  String get display => hypothesis.isEmpty
      ? committed
      : (committed.isEmpty ? hypothesis : '$committed $hypothesis');
}

// ---------------------------------------------------------------------------
// TSASREngine
// ---------------------------------------------------------------------------
/// Node-backed ASR: the SDK owns audio capture, VAD, turn endpointing and one
/// persistent decoder session natively. Pass model paths, call [start], read
/// [turns].
///
/// This is the mirror of Swift's `ASREngine(config:)`, and the counterpart to
/// [ASREngine] in `asr_engine.dart`, which is the *Current* push path where
/// your app owns the microphone and feeds PCM through `ASRStream.send`. Pick
/// this one unless you already have an audio pipeline of your own.
///
/// ```dart
/// final asr = TSASREngine();
/// asr.turns.listen((turn) => render(turn.display));
/// await asr.start(config: {
///   'vad': 'TheStageAI/silero-vad',
///   'stt': 'TheStageAI/thewhisper-large-v3-turbo',
///   'language': 'en',
/// });
/// // ...
/// await asr.stop();
/// ```
///
/// Streaming cadence, the commit ladder and VAD thresholds are deliberately
/// not configurable from Dart: the shipping policy is tuned per model, and
/// these are easy to get wrong.
class TSASREngine {
  static const MethodChannel _channel = MethodChannel(MethodChannels.main);
  static const EventChannel _turnsChannel = EventChannel(
    MethodChannels.asrEngineTurns,
  );
  static const EventChannel _transcriptsChannel = EventChannel(
    MethodChannels.asrEngineTranscripts,
  );
  static const EventChannel _partialsChannel = EventChannel(
    MethodChannels.asrEnginePartials,
  );
  static const EventChannel _vadProbsChannel = EventChannel(
    MethodChannels.asrEngineVADProbabilities,
  );
  static const EventChannel _eventsChannel = EventChannel(
    MethodChannels.asrEngineEvents,
  );

  bool _running = false;

  // -------------------------------------------------------------------------
  // Public Getters
  // -------------------------------------------------------------------------

  bool get is_running => _running;

  /// Every turn the decoder produces, partial and final. Subscribing before
  /// [start] is fine — the native side attaches the sink when the engine
  /// comes up.
  late final Stream<TSASRTurn> turns = _turnsChannel
      .receiveBroadcastStream()
      .map((e) => TSASRTurn.from_json(_as_map(e)));

  /// One final string per completed utterance.
  late final Stream<String> transcripts = _transcriptsChannel
      .receiveBroadcastStream()
      .map((e) => e.toString());

  /// Rewriteable caption text. Latest-value semantics — do not accumulate.
  late final Stream<String> partial_transcripts = _partialsChannel
      .receiveBroadcastStream()
      .map((e) => e.toString());

  /// Per-frame speech probability, for a level meter.
  late final Stream<double> vad_probabilities = _vadProbsChannel
      .receiveBroadcastStream()
      .map((e) => (e as num).toDouble());

  /// Lifecycle and error events (`kind` + `data`).
  late final Stream<Map<String, dynamic>> events = _eventsChannel
      .receiveBroadcastStream()
      .map((e) => _as_map(e));

  // -------------------------------------------------------------------------
  // Public Methods
  // -------------------------------------------------------------------------

  /// Load the models named in [config] and begin capturing.
  ///
  /// Recognised keys — every one optional, an absent key keeps the SDK's
  /// shipping policy:
  ///
  /// - `vad`, `stt` — HuggingFace engine paths
  /// - `vad_device`, `stt_device` — `npu` / `gpu` / `cpu`
  /// - `stt_revision` — pin a revision instead of the fleet pin
  /// - `language` — ISO code, or `auto`
  /// - `turn_silence_timeout_ms` — hush that ends a turn
  /// - `turn_asr_silence_hangover_ms` — trailing audio still sent to the
  ///   decoder, so the last word is not clipped
  Future<void> start({required Map<String, dynamic> config}) async {
    await _channel.invokeMethod<void>(MethodRoute.asrEngineStart, config);
    _running = true;
  }

  /// Stop capture and release the models the SDK loaded in [start].
  Future<void> stop() async {
    await _channel.invokeMethod<void>(MethodRoute.asrEngineStop);
    _running = false;
  }

  // -------------------------------------------------------------------------
  // Private Methods
  // -------------------------------------------------------------------------

  static Map<String, dynamic> _as_map(Object? value) {
    if (value is! Map) return {};
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
}
