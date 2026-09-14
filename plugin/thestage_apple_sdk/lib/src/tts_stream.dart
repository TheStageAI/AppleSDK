import 'inference_types.dart';
import 'thestage_flutter_sdk.dart';

// ---------------------------------------------------------------------------
// TTSStream
// ---------------------------------------------------------------------------
/// Already-open TTS push session. Drain [output] concurrently with
/// [close] — waiting for output after close on the same task
/// deadlocks on native.
class TTSStream {
  final String stream_id;
  final Stream<Map<String, dynamic>> output;

  TTSStream({required this.stream_id, required this.output});

  static Future<TTSStream> open({
    required String model_name,
    TTSGenerationConfig generation = const TTSGenerationConfig(),
    TTSStreamConfig? stream_config,
  }) async {
    final stream_id = await TheStageFlutterSDK.open_push_stream(
      model_name: model_name,
      kind: 'tts',
      input_json: {
        ...generation.to_json(),
        if (stream_config != null) 'stream_config': stream_config.to_json(),
      },
    );
    return TTSStream(
      stream_id: stream_id,
      output: TheStageFlutterSDK.events_for(stream_id),
    );
  }

  Future<void> send(String text) {
    return TheStageFlutterSDK.send(stream_id: stream_id, text: text);
  }

  Future<void> flush() {
    return TheStageFlutterSDK.flush_stream(stream_id: stream_id);
  }

  Future<void> close() {
    return TheStageFlutterSDK.close_stream(stream_id: stream_id);
  }

  Future<void> cancel() {
    return TheStageFlutterSDK.cancel_stream(stream_id: stream_id);
  }
}
