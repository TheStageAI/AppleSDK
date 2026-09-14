import 'dart:typed_data';

import 'asr_engine.dart';
import 'thestage_flutter_sdk.dart';

// ---------------------------------------------------------------------------
// ASRStreamEvent
// ---------------------------------------------------------------------------
class ASRStreamEvent {
  final String kind;
  final Map<String, dynamic> payload;

  const ASRStreamEvent({required this.kind, required this.payload});

  factory ASRStreamEvent.from_json(Map<String, dynamic> json) =>
      ASRStreamEvent(
        kind: (json['kind'] as String? ?? '').toLowerCase(),
        payload: json,
      );

  bool get is_begin => kind == 'begin';
  bool get is_turn => kind == 'turn';
  bool get is_termination => kind == 'termination';
  bool get is_partial => kind == 'partial';
}

// ---------------------------------------------------------------------------
// ASRStream
// ---------------------------------------------------------------------------
/// Already-open ASR push session. Session ids stay on the native
/// bridge; Dart only holds the handle.
class ASRStream {
  final String stream_id;
  final Stream<Map<String, dynamic>> _events;

  ASRStream({required this.stream_id, required Stream<Map<String, dynamic>> events})
      : _events = events;

  static Future<ASRStream> open({
    required String model_name,
    String? vad_model_name,
    ASRGenerationConfig generation = const ASRGenerationConfig(),
    ASRStreamingConfig streaming = const ASRStreamingConfig(),
  }) async {
    final stream_id = await TheStageFlutterSDK.open_push_stream(
      model_name: model_name,
      kind: 'asr',
      input_json: {
        ...generation.to_json(),
        'streaming': streaming.to_json(),
        if (vad_model_name != null) 'vad_model_name': vad_model_name,
      },
    );
    return ASRStream(
      stream_id: stream_id,
      events: TheStageFlutterSDK.events_for(stream_id),
    );
  }

  Stream<ASRStreamEvent> get events => _events.map(ASRStreamEvent.from_json);

  Future<void> send(Float32List pcm) {
    return TheStageFlutterSDK.send_pcm(stream_id: stream_id, pcm: pcm);
  }

  Future<void> flush() {
    return TheStageFlutterSDK.flush_stream(stream_id: stream_id);
  }

  Future<ASRResult> close() async {
    final payload = await TheStageFlutterSDK.close_stream(
      stream_id: stream_id,
    );
    return ASRResult.from_json(payload);
  }

  Future<void> cancel() {
    return TheStageFlutterSDK.cancel_stream(stream_id: stream_id);
  }
}
