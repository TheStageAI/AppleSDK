import 'dart:typed_data';

import 'asr_stream.dart';
import 'inference_types.dart';
import 'thestage_flutter_sdk.dart';

export 'inference_types.dart' show InferenceMetrics;

// ---------------------------------------------------------------------------
// ASR enums / configs (mirrors Swift)
// ---------------------------------------------------------------------------

enum ASRTimestampMode { NONE, SEGMENT, WORD }

enum ASRTextContext { NONE, SUBMITTED }

/// Live-commit policy.
///
/// Two algorithms: [NAIVE] (portable) and [THESTAGE_V5] (measured-clock
/// ladder). Older wire names (`THESTAGE`, `THESTAGE_V2`, `THESTAGE_V4`) are
/// accepted by the native side and resolve onto these.
enum ASRStreamingAlgorithm {
  /// The portable algorithm. Runs on any streaming pipeline; cuts the buffer
  /// at measured word ends only where the pipeline reports them.
  NAIVE,

  /// Measured-clock commit ladder. Needs word timestamps the pipeline
  /// measured rather than inferred.
  THESTAGE_V5,
}

enum ASRLocalAgreementMode { TOLERANT, CONSECUTIVE }

enum ASREndpointCommit { NONE, AGREED_PREFIX, FULL_HYPOTHESIS }

enum ASRConfirmationScope { SEGMENT_FIRST, WORDS_ONLY }

class ASRGenerationConfig {
  static const List<String> field_names = [
    'language',
    'timestamps',
    'max_new_tokens',
    'return_tokens',
    'text_context',
    'context_text',
    'decoder_prefix_text',
    'language_detection',
    'overlap',
  ];

  final String language;
  final ASRTimestampMode timestamps;
  final int? max_new_tokens;
  final bool return_tokens;
  final ASRTextContext text_context;
  final String context_text;
  final bool language_detection;
  final double overlap;

  const ASRGenerationConfig({
    this.language = 'en',
    this.timestamps = ASRTimestampMode.WORD,
    this.max_new_tokens,
    this.return_tokens = false,
    this.text_context = ASRTextContext.NONE,
    this.context_text = '',
    this.language_detection = false,
    this.overlap = 0.2,
  });

  Map<String, dynamic> to_json() => {
        'language': language,
        'timestamps': timestamps.name,
        if (max_new_tokens != null) 'max_new_tokens': max_new_tokens,
        'return_tokens': return_tokens,
        'text_context': text_context.name,
        'context_text': context_text,
        'language_detection': language_detection,
        'overlap': overlap,
      };
}

/// Live-session knobs. Every field is an override: `null` keeps
/// the loaded model's `for_pipeline` policy. An empty config is
/// `{}` on the wire so Swift applies 2.0 s (generic) or 1.2 s
/// (measured word times / SpeechKit), never a Dart hardcoded 5.0.
class ASRStreamingConfig {
  static const List<String> field_names = [
    'algorithm',
    'min_audio_s',
    'partial_s',
    'n_confirmations',
    'agreement_mode',
    'hold_n',
    'max_repeats',
    'stream_buffer_s',
    'commit_lag_s',
    'trim_overlap_s',
    'use_prefix',
    'speech_onset_s',
    'silence_hang_s',
    'endpoint_silence_s',
    'endpoint_commit',
    'flush_silence_s',
    'pause_flush_s',
    'format_turns',
    'min_turn_silence_ms',
    'max_turn_silence_ms',
    'cut_release_ratio',
    'soft_match_max_cer',
    'confirmation_scope',
    'segment_stall_passes',
    'carry_cut_punctuation',
  ];

  final ASRStreamingAlgorithm? algorithm;
  final double? min_audio_s;
  final double? partial_s;
  final int? n_confirmations;
  final ASRLocalAgreementMode? agreement_mode;
  final int? hold_n;
  final int? max_repeats;
  final double? stream_buffer_s;
  final double? commit_lag_s;
  final double? trim_overlap_s;
  final bool? use_prefix;
  final double? speech_onset_s;
  final double? silence_hang_s;
  final double? endpoint_silence_s;
  final ASREndpointCommit? endpoint_commit;
  final double? flush_silence_s;
  final double? pause_flush_s;
  final bool? format_turns;
  final int? min_turn_silence_ms;
  final int? max_turn_silence_ms;
  final double? cut_release_ratio;
  final double? soft_match_max_cer;
  final ASRConfirmationScope? confirmation_scope;
  final int? segment_stall_passes;
  final bool? carry_cut_punctuation;

  const ASRStreamingConfig({
    this.algorithm,
    this.min_audio_s,
    this.partial_s,
    this.n_confirmations,
    this.agreement_mode,
    this.hold_n,
    this.max_repeats,
    this.stream_buffer_s,
    this.commit_lag_s,
    this.trim_overlap_s,
    this.use_prefix,
    this.speech_onset_s,
    this.silence_hang_s,
    this.endpoint_silence_s,
    this.endpoint_commit,
    this.flush_silence_s,
    this.pause_flush_s,
    this.format_turns,
    this.min_turn_silence_ms,
    this.max_turn_silence_ms,
    this.cut_release_ratio,
    this.soft_match_max_cer,
    this.confirmation_scope,
    this.segment_stall_passes,
    this.carry_cut_punctuation,
  });

  Map<String, dynamic> to_json() => {
        if (algorithm != null) 'algorithm': algorithm!.name,
        if (min_audio_s != null) 'min_audio_s': min_audio_s,
        if (partial_s != null) 'partial_s': partial_s,
        if (n_confirmations != null) 'n_confirmations': n_confirmations,
        if (agreement_mode != null) 'agreement_mode': agreement_mode!.name,
        if (hold_n != null) 'hold_n': hold_n,
        if (max_repeats != null) 'max_repeats': max_repeats,
        if (stream_buffer_s != null) 'stream_buffer_s': stream_buffer_s,
        if (commit_lag_s != null) 'commit_lag_s': commit_lag_s,
        if (trim_overlap_s != null) 'trim_overlap_s': trim_overlap_s,
        if (use_prefix != null) 'use_prefix': use_prefix,
        if (speech_onset_s != null) 'speech_onset_s': speech_onset_s,
        if (silence_hang_s != null) 'silence_hang_s': silence_hang_s,
        if (endpoint_silence_s != null)
          'endpoint_silence_s': endpoint_silence_s,
        if (endpoint_commit != null)
          'endpoint_commit': endpoint_commit!.name,
        if (flush_silence_s != null) 'flush_silence_s': flush_silence_s,
        if (pause_flush_s != null) 'pause_flush_s': pause_flush_s,
        if (format_turns != null) 'format_turns': format_turns,
        if (min_turn_silence_ms != null)
          'min_turn_silence_ms': min_turn_silence_ms,
        if (max_turn_silence_ms != null)
          'max_turn_silence_ms': max_turn_silence_ms,
        if (cut_release_ratio != null)
          'cut_release_ratio': cut_release_ratio,
        if (soft_match_max_cer != null)
          'soft_match_max_cer': soft_match_max_cer,
        if (confirmation_scope != null)
          'confirmation_scope': confirmation_scope!.name,
        if (segment_stall_passes != null)
          'segment_stall_passes': segment_stall_passes,
        if (carry_cut_punctuation != null)
          'carry_cut_punctuation': carry_cut_punctuation,
      };
}

class ASRWord {
  final String text;
  final double t0;
  final double t1;
  final String? speaker_id;

  const ASRWord({
    required this.text,
    required this.t0,
    required this.t1,
    this.speaker_id,
  });

  factory ASRWord.from_json(Map<String, dynamic> json) => ASRWord(
        text: json['text'] as String? ?? '',
        t0: (json['t0'] as num?)?.toDouble() ?? 0,
        t1: (json['t1'] as num?)?.toDouble() ?? 0,
        speaker_id: json['speaker_id'] as String?,
      );
}

class ASRTokenStats {
  static const List<String> field_names = [
    'generated_tokens',
    'tokens_per_second',
    'prefill_seconds',
  ];

  final int generated_tokens;
  final double tokens_per_second;
  final double prefill_seconds;

  const ASRTokenStats({
    this.generated_tokens = 0,
    this.tokens_per_second = 0,
    this.prefill_seconds = 0,
  });

  factory ASRTokenStats.from_json(Map<String, dynamic> json) => ASRTokenStats(
        generated_tokens: (json['generated_tokens'] as num?)?.toInt() ?? 0,
        tokens_per_second:
            (json['tokens_per_second'] as num?)?.toDouble() ?? 0,
        prefill_seconds: (json['prefill_seconds'] as num?)?.toDouble() ?? 0,
      );
}

class ASRMetrics {
  static const List<String> field_names = [
    'preprocess_seconds',
    'encode_seconds',
    'decode_seconds',
    'total_seconds',
    'audio_seconds',
    'rtf',
    'chunk_count',
    'tokens',
  ];

  final double preprocess_seconds;
  final double encode_seconds;
  final double decode_seconds;
  final double total_seconds;
  final double audio_seconds;
  final double rtf;
  final int chunk_count;
  final ASRTokenStats? tokens;

  int get generated_tokens => tokens?.generated_tokens ?? 0;
  double get tokens_per_second => tokens?.tokens_per_second ?? 0;
  double get prefill_seconds => tokens?.prefill_seconds ?? 0;
  double get last_prefill_seconds => prefill_seconds;

  const ASRMetrics({
    this.preprocess_seconds = 0,
    this.encode_seconds = 0,
    this.decode_seconds = 0,
    this.total_seconds = 0,
    this.audio_seconds = 0,
    this.rtf = 0,
    this.chunk_count = 0,
    this.tokens,
  });

  factory ASRMetrics.from_json(Map<String, dynamic> json) {
    ASRTokenStats? tokens;
    final raw = json['tokens'];
    if (raw is Map<String, dynamic>) {
      tokens = ASRTokenStats.from_json(raw);
    } else if ((json['generated_tokens'] as num?)?.toInt() != null ||
        json['last_prefill_seconds'] != null ||
        json['tokens_per_second'] != null) {
      tokens = ASRTokenStats(
        generated_tokens: (json['generated_tokens'] as num?)?.toInt() ?? 0,
        tokens_per_second:
            (json['tokens_per_second'] as num?)?.toDouble() ?? 0,
        prefill_seconds:
            (json['last_prefill_seconds'] as num?)?.toDouble() ??
                (json['prefill_seconds'] as num?)?.toDouble() ??
                0,
      );
    }
    return ASRMetrics(
      preprocess_seconds:
          (json['preprocess_seconds'] as num?)?.toDouble() ?? 0,
      encode_seconds: (json['encode_seconds'] as num?)?.toDouble() ?? 0,
      decode_seconds: (json['decode_seconds'] as num?)?.toDouble() ?? 0,
      total_seconds: (json['total_seconds'] as num?)?.toDouble() ?? 0,
      audio_seconds: (json['audio_seconds'] as num?)?.toDouble() ?? 0,
      rtf: (json['rtf'] as num?)?.toDouble() ?? 0,
      chunk_count: (json['chunk_count'] as num?)?.toInt() ?? 0,
      tokens: tokens,
    );
  }

  static const zero = ASRMetrics();
}

class ASRResult {
  static const List<String> field_names = [
    'text',
    'words',
    'timestamp_mode',
    'tokens',
    'metrics',
    'language',
    'generated_tokens',
    'decode_seconds',
  ];

  final String text;
  final List<ASRWord>? words;
  final ASRTimestampMode timestamp_mode;
  final List<int>? tokens;
  final ASRMetrics metrics;
  final String? language;
  final int generated_tokens;
  final double decode_seconds;

  const ASRResult({
    required this.text,
    this.words,
    this.timestamp_mode = ASRTimestampMode.NONE,
    this.tokens,
    this.metrics = ASRMetrics.zero,
    this.language,
    this.generated_tokens = 0,
    this.decode_seconds = 0,
  });

  @Deprecated('Use generated_tokens')
  int get token_count => generated_tokens;

  factory ASRResult.from_json(Map<String, dynamic> json) {
    final raw_words = json['words'];
    final raw_metrics = json['metrics'];
    final generated = (json['generated_tokens'] as num?)?.toInt() ??
        (json['token_count'] as num?)?.toInt() ??
        0;
    return ASRResult(
      text: (json['text'] ?? json['transcription'] ?? '') as String,
      words: raw_words is List
          ? raw_words
              .whereType<Map>()
              .map((w) => ASRWord.from_json(Map<String, dynamic>.from(w)))
              .toList()
          : null,
      timestamp_mode: ASRTimestampMode.values.firstWhere(
        (m) => m.name == json['timestamp_mode'],
        orElse: () => ASRTimestampMode.NONE,
      ),
      tokens: (json['tokens'] as List?)?.cast<int>(),
      metrics: raw_metrics is Map
          ? ASRMetrics.from_json(Map<String, dynamic>.from(raw_metrics))
          : ASRMetrics.zero,
      language: json['language'] as String?,
      generated_tokens: generated,
      decode_seconds: (json['decode_seconds'] as num?)?.toDouble() ?? 0,
    );
  }
}

// ---------------------------------------------------------------------------
// ASREngine
// ---------------------------------------------------------------------------
/// Composition handle: already-loaded `stt` (+ optional `vad`).
/// `start_model` only loads those models — there is no
/// `model_type: thestage_asr_engine`.
class ASREngine {
  final String stt;
  final String? vad;

  ASREngine({required this.stt, this.vad});

  Future<ASRResult> infer(
    Float32List audio, {
    ASRGenerationConfig config = const ASRGenerationConfig(),
  }) async {
    final rows = await TheStageFlutterSDK.infer(
      model_name: stt,
      input_json: {
        'audio': audio,
        ...config.to_json(),
        if (vad != null) 'vad_model_name': vad,
      },
    );
    if (rows.isEmpty) {
      return const ASRResult(text: '');
    }
    return ASRResult.from_json(rows.first);
  }

  Future<ASRStream> open_stream({
    ASRGenerationConfig generation = const ASRGenerationConfig(),
    ASRStreamingConfig streaming = const ASRStreamingConfig(),
  }) {
    return ASRStream.open(
      model_name: stt,
      vad_model_name: vad,
      generation: generation,
      streaming: streaming,
    );
  }
}
