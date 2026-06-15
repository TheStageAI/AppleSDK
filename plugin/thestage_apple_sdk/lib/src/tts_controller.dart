import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

// ---------------------------------------------------------------------------
// TTSStreamStats
// ---------------------------------------------------------------------------
class TTSStreamStats {
  final int generatedTokens;
  final double? timeToFirstAudio;
  final double? totalTime;
  final double audioDuration;
  final double? tokensPerSecond;

  /// Process `phys_footprint` in MB — the metric iOS jetsam terminates against
  /// and the one Xcode's memory gauge shows (counts compressed + IOKit/ANE
  /// memory). This is the headline "Memory" number.
  final double? memoryMB;

  /// Resident set size (RSS) in MB — pages currently in physical RAM,
  /// excluding compressed/IOKit memory. Always <= [memoryMB]; kept as a
  /// secondary diagnostic only (it is NOT the termination metric).
  final double? residentMB;

  const TTSStreamStats({
    required this.generatedTokens,
    this.timeToFirstAudio,
    this.totalTime,
    required this.audioDuration,
    this.tokensPerSecond,
    this.memoryMB,
    this.residentMB,
  });

  double? get rtf =>
      (totalTime != null && totalTime! > 0) ? audioDuration / totalTime! : null;
}

// ---------------------------------------------------------------------------
// TTSController
// ---------------------------------------------------------------------------
/// Reusable TTS controller for any Flutter app needing streaming text-to-speech.
///
/// Wraps the native TTSSession via the thestage_apple_sdk plugin. Manages model lifecycle,
/// voice switching, streaming audio playback, and metrics collection.
///
/// Usage:
/// ```dart
/// final tts = TTSController(
///   enginesPath: 'TheStageAI/neutts-multilingual',
///   modelType: 'neutts-multilingual',
///   revision: 'develop',
/// );
/// await tts.initialize();
/// await tts.startStream('Hello world!');
/// ```
class TTSController extends ChangeNotifier {
  final String modelName;
  final String enginesPath;
  final String? modelType;
  final String revision;
  final int sampleRate;
  final List<String> availableVoices;

  final TheStageAudioPlayer _player;

  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------
  String _status = 'Idle';
  String _selectedVoice;
  String? _loadedVoice;
  bool _modelReady = false;
  bool _generating = false;
  double _downloadProgress = 0.0;
  String? _loadPhase;
  TTSStreamStats? _stats;

  // Latest memory sample (phys_footprint + RSS), refreshed asynchronously
  // during streaming since the native call is async and stats are built
  // synchronously per chunk.
  double? _footprintMB;
  double? _residentMB;

  StreamSubscription<Map<String, dynamic>>? _streamSub;

  // -------------------------------------------------------------------------
  // Public Getters
  // -------------------------------------------------------------------------
  String get status => _status;
  String get selectedVoice => _selectedVoice;
  bool get modelReady => _modelReady;
  bool get generating => _generating;
  double get downloadProgress => _downloadProgress;

  /// Current load phase: `downloading`, `extracting`, `loading`, `ready`,
  /// or `null` when not loading. Only `downloading` carries a meaningful
  /// [downloadProgress] fraction; the others are coarse/blocking, so render
  /// an indeterminate indicator for them.
  String? get loadPhase => _loadPhase;
  TTSStreamStats? get stats => _stats;

  // -------------------------------------------------------------------------
  // Constructor
  // -------------------------------------------------------------------------
  TTSController({
    this.modelName = 'neutts',
    this.enginesPath = 'TheStageAI/neutts-multilingual',
    this.modelType = 'neutts-multilingual',
    this.revision = 'develop',
    this.sampleRate = 24000,
    this.availableVoices = const ['dave', 'jo', 'paul', 'bril'],
    String? defaultVoice,
  })  : _selectedVoice = defaultVoice ?? 'dave',
        _player = TheStageAudioPlayer(sampleRate: sampleRate);

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Initialize the SDK and load the TTS model with the selected voice.
  Future<void> initialize({String? apiToken}) async {
    _setStatus('Initializing SDK...');

    if (apiToken != null) {
      await TheStageFlutterSDK.initialize(api_token: apiToken);
    }

    // The SDK reports a `phase` (downloading -> extracting -> loading ->
    // ready) alongside the fraction. Track it so consumers can show the
    // compile/load stage instead of sitting on "Downloading..." while
    // CoreML specialises the model.
    final progressSub = TheStageFlutterSDK.on_progress.listen((event) {
      _downloadProgress = (event['progress'] as num?)?.toDouble() ?? 0.0;
      _loadPhase = event['phase'] as String?;
      _setStatus(statusForPhase(_loadPhase));
    });

    _setStatus('Loading model...');
    try {
      await _loadModel(_selectedVoice);
    } catch (e) {
      _setStatus('Error: $e');
      await progressSub.cancel();
      return;
    }
    await progressSub.cancel();

    _downloadProgress = 0.0;
    _loadPhase = null;
    _modelReady = true;
    _setStatus('Ready');
  }

  /// Switch to a different TTS voice.
  Future<void> switchVoice(String voice) async {
    if (voice == _loadedVoice) return;
    _selectedVoice = voice;
    _modelReady = false;
    _setStatus('Switching to $voice...');

    await _loadModel(voice);

    _modelReady = true;
    _setStatus('Ready');
  }

  // -------------------------------------------------------------------------
  // Streaming
  // -------------------------------------------------------------------------

  /// Start streaming TTS for the given text. Audio plays through the built-in player.
  Future<void> startStream(String text) async {
    if (text.isEmpty || !_modelReady) return;

    _generating = true;
    _stats = null;
    _setStatus('Streaming...');
    if (_player.isPlaying) await _player.stop();
    await _player.start();

    // Prime a memory sample so the first chunk has a value to show.
    unawaited(_refreshMemory());

    _streamSub = TheStageFlutterSDK.infer_stream(
      model_name: modelName,
      input_json: {'text': text},
    ).listen(
      (chunk) {
        // Plugin emits audio as Float32 typed bytes (matches the
        // `[Float]` chunks the SDK produces). Casting to Float64List
        // here previously threw on every chunk and silently aborted
        // this listener before the `is_final` branch ran.
        final audio = chunk['audio'] as Float32List?;
        final isFinal = chunk['is_final'] as bool? ?? false;

        if (audio != null && audio.isNotEmpty) {
          _player.enqueue(audio);
        }

        _stats = TTSStreamStats(
          generatedTokens: (chunk['generated_tokens'] as num?)?.toInt() ?? 0,
          timeToFirstAudio:
              (chunk['time_to_first_token'] as num?)?.toDouble(),
          totalTime: (chunk['total_seconds'] as num?)?.toDouble(),
          audioDuration: _computeAudioDuration(chunk),
          tokensPerSecond:
              (chunk['tokens_per_second'] as num?)?.toDouble(),
          // Memory is `phys_footprint` (the metric iOS jetsam kills against),
          // sampled asynchronously via the plugin. RSS is kept as a secondary
          // diagnostic. Values lag by at most one chunk since the native read
          // is async and stats are built synchronously here.
          memoryMB: _footprintMB,
          residentMB: _residentMB,
        );
        notifyListeners();
        // Refresh the sample for the next chunk (fire-and-forget).
        unawaited(_refreshMemory());

        if (isFinal) {
          _player.drain().then((_) {
            _generating = false;
            _setStatus('Done');
          });
        }
      },
      onError: (error) {
        _generating = false;
        _setStatus('Error: $error');
      },
    );
  }

  /// Stop the current stream and playback.
  Future<void> stopStream() async {
    _streamSub?.cancel();
    _streamSub = null;
    await _player.stop();
    _generating = false;
    _setStatus(_modelReady ? 'Ready' : _status);
  }

  // -------------------------------------------------------------------------
  // Cleanup
  // -------------------------------------------------------------------------
  @override
  void dispose() {
    _streamSub?.cancel();
    _player.stop();
    if (_modelReady) {
      TheStageFlutterSDK.stop_model(model_name: modelName);
    }
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Private Helpers
  // -------------------------------------------------------------------------
  Future<void> _loadModel(String voiceId) async {
    if (_loadedVoice != null) {
      await TheStageFlutterSDK.stop_model(model_name: modelName);
    }
    await TheStageFlutterSDK.start_model(
      model_name: modelName,
      engines_path: enginesPath,
      model_type: modelType,
      revision: revision,
      config: {'voice_id': voiceId},
    );
    _loadedVoice = voiceId;
  }

  /// Sample process memory via the plugin's native `task_vm_info` reader and
  /// cache it. `phys_footprint` (the iOS termination metric) becomes the
  /// headline number; RSS is kept as a secondary diagnostic. Falls back to
  /// Dart's `ProcessInfo.currentRss` (RSS only) if the native call is
  /// unavailable.
  Future<void> _refreshMemory() async {
    try {
      final mem = await TheStageFlutterSDK.memory_footprint();
      if (mem != null) {
        _footprintMB = mem['footprint_mb'];
        _residentMB = mem['resident_mb'];
        return;
      }
    } catch (_) {
      // Fall through to the RSS-only fallback below.
    }
    try {
      final rss = ProcessInfo.currentRss;
      if (rss > 0) {
        _residentMB = rss / (1024 * 1024);
        // No footprint available; surface RSS as the memory number so the
        // UI isn't blank, but it under-reports vs the kill metric.
        _footprintMB ??= _residentMB;
      }
    } catch (_) {
      // Leave the last known values in place.
    }
  }

  double _computeAudioDuration(Map<String, dynamic> chunk) {
    final audio = chunk['audio'] as Float32List?;
    final sr = (chunk['sample_rate'] as num?)?.toInt() ?? sampleRate;
    final prev = _stats?.audioDuration ?? 0.0;
    if (audio == null || audio.isEmpty) return prev;
    return prev + audio.length / sr;
  }

  /// Default human-readable status for a load [phase]. Apps that want
  /// localized or custom copy can read [loadPhase] directly instead.
  static String statusForPhase(String? phase) {
    switch (phase) {
      case 'downloading':
        return 'Downloading engines...';
      case 'extracting':
        return 'Extracting engines...';
      case 'loading':
        return 'Loading & compiling model...';
      case 'ready':
        return 'Ready';
      default:
        return 'Loading model...';
    }
  }

  void _setStatus(String value) {
    _status = value;
    notifyListeners();
  }
}
