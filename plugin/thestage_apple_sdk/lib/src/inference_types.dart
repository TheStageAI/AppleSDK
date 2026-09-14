// ---------------------------------------------------------------------------
// SamplingParams
// ---------------------------------------------------------------------------
/// Shared sampling knobs. Sampler defaults are 1.0 / 0; LLM seeds
/// 0.7 / 20 on [LLMGenerationConfig]. TTS empty config keeps
/// `sampling == null` so the pipeline default wins.
class SamplingParams {
  static const List<String> field_names = [
    'temperature',
    'top_k',
    'top_p',
    'min_p',
    'repetition_penalty',
  ];

  final double temperature;
  final int top_k;
  final double top_p;
  final double min_p;
  final double repetition_penalty;

  const SamplingParams({
    this.temperature = 1.0,
    this.top_k = 0,
    this.top_p = 1.0,
    this.min_p = 0.0,
    this.repetition_penalty = 1.0,
  });

  Map<String, dynamic> to_json() => {
        'temperature': temperature,
        'top_k': top_k,
        'top_p': top_p,
        'min_p': min_p,
        'repetition_penalty': repetition_penalty,
      };
}

// ---------------------------------------------------------------------------
// InferenceMetrics
// ---------------------------------------------------------------------------
class InferenceMetrics {
  static const List<String> field_names = [
    'total_seconds',
    'prefill_seconds',
    'decode_seconds',
    'encode_seconds',
    'prompt_tokens',
    'generated_tokens',
    'tokens_per_second',
  ];

  final double total_seconds;
  final double prefill_seconds;
  final double decode_seconds;
  final double encode_seconds;
  final int prompt_tokens;
  final int generated_tokens;
  final double tokens_per_second;

  const InferenceMetrics({
    this.total_seconds = 0,
    this.prefill_seconds = 0,
    this.decode_seconds = 0,
    this.encode_seconds = 0,
    this.prompt_tokens = 0,
    this.generated_tokens = 0,
    this.tokens_per_second = 0,
  });

  factory InferenceMetrics.from_json(Map<String, dynamic> json) =>
      InferenceMetrics(
        total_seconds: (json['total_seconds'] as num?)?.toDouble() ?? 0,
        prefill_seconds: (json['prefill_seconds'] as num?)?.toDouble() ?? 0,
        decode_seconds: (json['decode_seconds'] as num?)?.toDouble() ?? 0,
        encode_seconds: (json['encode_seconds'] as num?)?.toDouble() ?? 0,
        prompt_tokens: (json['prompt_tokens'] as num?)?.toInt() ?? 0,
        generated_tokens: (json['generated_tokens'] as num?)?.toInt() ?? 0,
        tokens_per_second:
            (json['tokens_per_second'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> to_json() => {
        'total_seconds': total_seconds,
        'prefill_seconds': prefill_seconds,
        'decode_seconds': decode_seconds,
        'encode_seconds': encode_seconds,
        'prompt_tokens': prompt_tokens,
        'generated_tokens': generated_tokens,
        'tokens_per_second': tokens_per_second,
      };
}

// ---------------------------------------------------------------------------
// LLMGenerationConfig
// ---------------------------------------------------------------------------
class LLMGenerationConfig {
  static const List<String> field_names = [
    'max_new_tokens',
    'min_new_tokens',
    'sampling',
    'seed',
    'enable_thinking',
    'stop_sequences',
  ];

  final int max_new_tokens;
  final int min_new_tokens;
  final SamplingParams sampling;
  final int? seed;
  final bool enable_thinking;
  final List<String> stop_sequences;

  LLMGenerationConfig({
    this.max_new_tokens = 512,
    this.min_new_tokens = 0,
    SamplingParams? sampling,
    double temperature = 0.7,
    int top_k = 20,
    double top_p = 1.0,
    double min_p = 0.0,
    double repetition_penalty = 1.0,
    this.seed,
    this.enable_thinking = true,
    this.stop_sequences = const [],
  }) : sampling = sampling ??
            SamplingParams(
              temperature: temperature,
              top_k: top_k,
              top_p: top_p,
              min_p: min_p,
              repetition_penalty: repetition_penalty,
            );

  Map<String, dynamic> to_json() => {
        'max_new_tokens': max_new_tokens,
        'min_new_tokens': min_new_tokens,
        'sampling': sampling.to_json(),
        if (seed != null) 'seed': seed,
        'enable_thinking': enable_thinking,
        'stop_sequences': stop_sequences,
      };
}

// ---------------------------------------------------------------------------
// LLMResult
// ---------------------------------------------------------------------------
class LLMResult {
  static const List<String> field_names = [
    'text',
    'prompt_tokens',
    'generated_tokens',
    'prefill_seconds',
    'decode_seconds',
    'decode_step_count',
    'decode_forward_seconds',
    'stop_reason',
    'encode_seconds',
    'tool_calls',
    'thinking',
    'final_text',
  ];

  final String text;
  final int prompt_tokens;
  final int generated_tokens;
  final double prefill_seconds;
  final double decode_seconds;
  final int decode_step_count;
  final double decode_forward_seconds;
  final String stop_reason;
  final double? encode_seconds;
  final List<Map<String, dynamic>> tool_calls;
  final String? thinking;
  final String final_text;

  const LLMResult({
    required this.text,
    this.prompt_tokens = 0,
    this.generated_tokens = 0,
    this.prefill_seconds = 0,
    this.decode_seconds = 0,
    this.decode_step_count = 0,
    this.decode_forward_seconds = 0,
    this.stop_reason = 'unknown',
    this.encode_seconds,
    this.tool_calls = const [],
    this.thinking,
    String? final_text,
  }) : final_text = final_text ?? text;

  factory LLMResult.from_json(Map<String, dynamic> json) {
    final raw_tools = json['tool_calls'];
    return LLMResult(
      text: json['text'] as String? ?? '',
      prompt_tokens: (json['prompt_tokens'] as num?)?.toInt() ?? 0,
      generated_tokens: (json['generated_tokens'] as num?)?.toInt() ?? 0,
      prefill_seconds: (json['prefill_seconds'] as num?)?.toDouble() ?? 0,
      decode_seconds: (json['decode_seconds'] as num?)?.toDouble() ?? 0,
      decode_step_count: (json['decode_step_count'] as num?)?.toInt() ?? 0,
      decode_forward_seconds:
          (json['decode_forward_seconds'] as num?)?.toDouble() ?? 0,
      stop_reason: json['stop_reason'] as String? ?? 'unknown',
      encode_seconds: (json['encode_seconds'] as num?)?.toDouble(),
      tool_calls: raw_tools is List
          ? raw_tools
              .whereType<Map>()
              .map((t) => Map<String, dynamic>.from(t))
              .toList()
          : const [],
      thinking: json['thinking'] as String?,
      final_text: json['final_text'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// TTSGenerationConfig
// ---------------------------------------------------------------------------
/// `sampling == null` (and omitted JSON) keeps the pipeline default.
class TTSGenerationConfig {
  static const List<String> field_names = [
    'sampling',
    'min_new_tokens',
    'max_context_length',
    'seed',
    'return_debug_info',
    'sample_rate_out',
    'temperature',
    'top_k',
  ];

  final SamplingParams? sampling;
  final int? min_new_tokens;
  final int? max_context_length;
  final int? seed;
  final bool return_debug_info;
  final int? sample_rate_out;
  @Deprecated('Use sampling.temperature')
  final double? temperature;
  @Deprecated('Use sampling.top_k')
  final int? top_k;

  const TTSGenerationConfig({
    this.sampling,
    this.min_new_tokens,
    this.max_context_length,
    this.seed,
    this.return_debug_info = false,
    this.sample_rate_out,
    this.temperature,
    this.top_k,
  });

  Map<String, dynamic> to_json() => {
        if (sampling != null) 'sampling': sampling!.to_json(),
        if (min_new_tokens != null) 'min_new_tokens': min_new_tokens,
        if (max_context_length != null)
          'max_context_length': max_context_length,
        if (seed != null) 'seed': seed,
        'return_debug_info': return_debug_info,
        if (sample_rate_out != null) 'sample_rate_out': sample_rate_out,
        if (temperature != null) 'temperature': temperature,
        if (top_k != null) 'top_k': top_k,
      };
}

// ---------------------------------------------------------------------------
// TTSResult
// ---------------------------------------------------------------------------
class TTSResult {
  static const List<String> field_names = [
    'samples',
    'sample_rate',
    'duration',
    'rtf',
    'tokens_per_second',
    'prompt_tokens',
    'generated_tokens',
    'prefill_seconds',
    'decode_seconds',
    'codec_seconds',
    'debug_info',
  ];

  final List<double> samples;
  final int sample_rate;
  final double duration;
  final double rtf;
  final double tokens_per_second;
  final int prompt_tokens;
  final int generated_tokens;
  final double prefill_seconds;
  final double decode_seconds;
  final double codec_seconds;
  final Map<String, dynamic>? debug_info;

  const TTSResult({
    this.samples = const [],
    required this.sample_rate,
    this.duration = 0,
    this.rtf = 0,
    this.tokens_per_second = 0,
    this.prompt_tokens = 0,
    this.generated_tokens = 0,
    this.prefill_seconds = 0,
    this.decode_seconds = 0,
    this.codec_seconds = 0,
    this.debug_info,
  });

  factory TTSResult.from_json(Map<String, dynamic> json) {
    final raw = json['samples'];
    return TTSResult(
      samples: raw is List
          ? raw.map((s) => (s as num).toDouble()).toList()
          : const [],
      sample_rate: (json['sample_rate'] as num?)?.toInt() ?? 0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      rtf: (json['rtf'] as num?)?.toDouble() ?? 0,
      tokens_per_second: (json['tokens_per_second'] as num?)?.toDouble() ?? 0,
      prompt_tokens: (json['prompt_tokens'] as num?)?.toInt() ?? 0,
      generated_tokens: (json['generated_tokens'] as num?)?.toInt() ?? 0,
      prefill_seconds: (json['prefill_seconds'] as num?)?.toDouble() ?? 0,
      decode_seconds: (json['decode_seconds'] as num?)?.toDouble() ?? 0,
      codec_seconds: (json['codec_seconds'] as num?)?.toDouble() ?? 0,
      debug_info: json['debug_info'] is Map
          ? Map<String, dynamic>.from(json['debug_info'] as Map)
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// TTSStreamConfig
// ---------------------------------------------------------------------------
class TTSStreamConfig {
  static const List<String> field_names = [
    'frames_per_chunk',
    'first_frames_per_chunk',
    'lookforward',
    'lookback',
    'overlap_frames',
    'chunk_frames_schedule',
  ];

  final int frames_per_chunk;
  final int? first_frames_per_chunk;
  final int lookforward;
  final int lookback;
  final int overlap_frames;

  /// Frames per chunk for the first chunks of every sentence (a ramp toward
  /// [frames_per_chunk]); null keeps the model's own schedule.
  final List<int>? chunk_frames_schedule;

  const TTSStreamConfig({
    this.frames_per_chunk = 25,
    this.first_frames_per_chunk = 25,
    this.lookforward = 5,
    this.lookback = 50,
    this.overlap_frames = 1,
    this.chunk_frames_schedule,
  });

  Map<String, dynamic> to_json() => {
        'frames_per_chunk': frames_per_chunk,
        if (first_frames_per_chunk != null)
          'first_frames_per_chunk': first_frames_per_chunk,
        'lookforward': lookforward,
        'lookback': lookback,
        'overlap_frames': overlap_frames,
        if (chunk_frames_schedule != null)
          'chunk_frames_schedule': chunk_frames_schedule,
      };
}
