import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

import '../nodes/event_log_node.dart';
import '../nodes/vlm_caption_node.dart';
import 'demo_settings.dart';
import 'model_roster.dart';

/// Recipe runner for custom nodes + ModelRoster + audio knobs.
class DemoController extends ChangeNotifier {
  DemoController(this.settings) {
    _agent = TheStageVoiceAgentFlutter();
    _eventSub = _agent.events.listen(_onAgentEvent);
    _progressSub = TheStageFlutterSDK.on_progress.listen(_onProgress);
  }

  final DemoSettings settings;
  late final TheStageVoiceAgentFlutter _agent;
  StreamSubscription? _eventSub;
  StreamSubscription? _progressSub;
  StreamSubscription? _captionSub;

  ModelRoster? roster;
  VLMCaptionNode? vlm;
  EventLogNode? eventLog;

  final List<String> busEvents = [];
  final List<String> captions = [];
  String? captionFilePath;
  String? status;
  String? error;
  double? downloadProgress;
  String? downloadPhase;
  bool running = false;
  TheStageAgentState agentState = TheStageAgentState.idle;

  Future<void> start() async {
    error = null;
    status = 'Preparing models…';
    notifyListeners();

    final r = ModelRoster([
      ModelSlot(
        name: 'vad',
        enginesPath: settings.vad,
        modelType: 'silero_vad',
        policy: ModelPolicy.resident,
      ),
      ModelSlot(
        name: 'stt',
        enginesPath: settings.stt,
        modelType: 'whisper',
        policy: ModelPolicy.resident,
      ),
      ModelSlot(
        name: 'tts',
        enginesPath: settings.tts,
        modelType: 'qwen3_tts',
        policy: ModelPolicy.resident,
      ),
      ModelSlot(
        name: 'llm',
        enginesPath: settings.llm,
        modelType: 'thestage_llm',
        policy: ModelPolicy.resident,
      ),
      ModelSlot(
        name: 'vlm',
        enginesPath: settings.vlm,
        modelType: 'thestage_vl',
        policy: ModelPolicy.ephemeral,
      ),
      ModelSlot(
        name: 'aec',
        enginesPath: settings.aecEnginesPath,
        modelType: 'neural-aec',
        policy: ModelPolicy.warmDisk,
      ),
    ]);
    roster = r;

    try {
      await r.prepare(
        onProgress: (name, p) {
          status = 'prepare $name ${(p * 100).round()}%';
          notifyListeners();
        },
      );
    } catch (e) {
      // Prefetch may fail for neural-aec model_type on some catalogs;
      // agent path still resolves via NeuralAecSession.
      debugPrint('prepare warning: $e');
    }

    final docs = await getApplicationDocumentsDirectory();
    final captionFile = File('${docs.path}/captions.txt');
    captionFilePath = captionFile.path;
    final sink = captionFile.openWrite(mode: FileMode.append);

    eventLog = EventLogNode(
      onBusEvent: (e) {
        final line = '${e['kind']}: $e';
        busEvents.insert(0, line);
        if (busEvents.length > 80) {
          busEvents.removeRange(80, busEvents.length);
        }
        notifyListeners();
      },
    );

    vlm = VLMCaptionNode(
      enginesPath: settings.vlm,
      // Quiet states only — do not caption during thinking / speaking.
      runWhen: const ['idle', 'sleeping', 'listening'],
      lifecycle: VlmLifecycle.external,
    );
    await _captionSub?.cancel();
    _captionSub = vlm!.captions.listen((c) {
      captions.insert(0, c);
      sink.writeln('${DateTime.now().toIso8601String()}\t$c');
      notifyListeners();
    });

    status = 'Starting agent pipeline…';
    notifyListeners();

    await _agent.start(
      config: settings.toAgentConfig(),
      extraNodes: [vlm!, eventLog!],
    );

    status = 'Loading LLM…';
    notifyListeners();
    await r.ensureHot(['llm']);

    await _agent.beginListening();
    running = true;
    status = 'Listening';
    notifyListeners();
  }

  Future<void> stop() async {
    await _agent.stop();
    await roster?.release(['llm', 'vlm']);
    await _captionSub?.cancel();
    _captionSub = null;
    running = false;
    status = 'Stopped';
    notifyListeners();
  }

  Future<void> captionImage(String path) async {
    final node = vlm;
    final r = roster;
    if (node == null || r == null) return;
    status = 'Waiting for quiet agent state…';
    notifyListeners();
    try {
      await _waitUntilQuiet();
      status = 'VLM ephemeral (park LLM/STT/TTS)…';
      notifyListeners();
      await r.withEphemeralSwap(
        'vlm',
        park: const ['llm', 'stt', 'tts'],
        body: () async {
          node.markReady(ready: true);
          await node.submitImage(path: path);
        },
      );
    } catch (e) {
      error = e.toString();
    } finally {
      node.markReady(ready: false);
      status = running ? 'Listening' : status;
      notifyListeners();
    }
  }

  /// Block until the agent is not in an active turn (thinking / speaking).
  Future<void> _waitUntilQuiet({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    bool quiet(TheStageAgentState s) =>
        s == TheStageAgentState.idle ||
        s == TheStageAgentState.sleeping ||
        s == TheStageAgentState.listening;
    if (quiet(agentState)) return;
    final done = Completer<void>();
    late StreamSubscription sub;
    sub = _agent.events.listen((e) {
      if (e['kind'] != 'state_changed') return;
      final s = TheStageAgentState.fromString(
        e['state']?.toString() ?? 'idle',
      );
      agentState = s;
      if (quiet(s) && !done.isCompleted) done.complete();
    });
    try {
      await done.future.timeout(timeout);
    } finally {
      await sub.cancel();
    }
  }

  Future<void> sendText(String text) async {
    await _agent.sendRequest(text);
  }

  void _onAgentEvent(Map<String, dynamic> e) {
    if (e['kind'] == 'state_changed') {
      agentState = TheStageAgentState.fromString(
        e['state']?.toString() ?? 'idle',
      );
    }
    if (e['kind'] == 'error') {
      error = e['message']?.toString();
    }
    notifyListeners();
  }

  void _onProgress(Map<String, dynamic> e) {
    downloadPhase = e['phase']?.toString();
    final p = e['progress'];
    downloadProgress = p is num ? p.toDouble() : null;
    notifyListeners();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _progressSub?.cancel();
    _captionSub?.cancel();
    _agent.dispose();
    super.dispose();
  }
}
