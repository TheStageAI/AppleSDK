import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

import 'backend/demo_controller.dart';
import 'backend/demo_settings.dart';

// Secrets via:
//   flutter run --dart-define-from-file=secrets.json
const _apiToken = String.fromEnvironment('TS_API_TOKEN');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CustomNodesDemoApp());
}

class CustomNodesDemoApp extends StatelessWidget {
  const CustomNodesDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Custom Nodes Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F6F5B)),
        useMaterial3: true,
      ),
      home: const DemoHome(),
    );
  }
}

class DemoHome extends StatefulWidget {
  const DemoHome({super.key});

  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> {
  late final DemoSettings _settings;
  DemoController? _controller;
  final _textCtrl = TextEditingController();
  String? _initError;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _settings = DemoSettings();
    _initialize();
  }

  Future<void> _initialize() async {
    if (_apiToken.isEmpty) {
      setState(() {
        _initError =
            'TS_API_TOKEN not set.\n'
            'flutter run --dart-define-from-file=secrets.json';
      });
      return;
    }
    try {
      await TheStageFlutterSDK.initialize(api_token: _apiToken);
      _controller = DemoController(_settings);
      setState(() => _ready = true);
    } catch (e) {
      setState(() => _initError = e.toString());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _settings.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Scaffold(body: Center(child: Text(_initError!)));
    }
    if (!_ready || _controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final c = _controller!;
    return ListenableBuilder(
      listenable: Listenable.merge([_settings, c]),
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Voice Agent — Custom Nodes'),
            actions: [
              IconButton(
                tooltip: c.running ? 'Stop' : 'Start',
                onPressed: () async {
                  if (c.running) {
                    await c.stop();
                  } else {
                    await c.start();
                  }
                },
                icon: Icon(c.running ? Icons.stop : Icons.play_arrow),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Status: ${c.status ?? '—'} · ${c.agentState.name}'),
              if (c.error != null)
                Text(c.error!, style: const TextStyle(color: Colors.red)),
              if (c.downloadProgress != null)
                LinearProgressIndicator(value: c.downloadProgress),
              const SizedBox(height: 12),
              _AudioSettings(settings: _settings, enabled: !c.running),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      decoration: const InputDecoration(
                        labelText: 'sendRequest text',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: c.running
                        ? () async {
                            final t = _textCtrl.text.trim();
                            if (t.isEmpty) return;
                            await c.sendText(t);
                            _textCtrl.clear();
                          }
                        : null,
                    child: const Text('Send'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: c.running
                    ? () async {
                        final picker = ImagePicker();
                        final file = await picker.pickImage(
                          source: ImageSource.gallery,
                        );
                        if (file == null) return;
                        await c.captionImage(file.path);
                      }
                    : null,
                icon: const Icon(Icons.image),
                label: const Text('Pick image → VLM caption'),
              ),
              if (c.captionFilePath != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SelectableText(
                    'Captions file: ${c.captionFilePath}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 16),
              Text('Captions', style: Theme.of(context).textTheme.titleMedium),
              ...c.captions.take(8).map(
                    (e) => ListTile(dense: true, title: Text(e)),
                  ),
              const SizedBox(height: 8),
              Text(
                'Bus events (onEvent)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ...c.busEvents.take(20).map(
                    (e) => Text(
                      e,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              const SizedBox(height: 8),
              Text(
                'Roster hot: ${c.roster?.hot.join(', ') ?? '—'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AudioSettings extends StatelessWidget {
  const _AudioSettings({required this.settings, required this.enabled});

  final DemoSettings settings;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Audio (applies on next start)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final hz in [16000, 24000, 48000])
              ChoiceChip(
                label: Text('${hz ~/ 1000} kHz out'),
                selected: settings.sampleRateOut == hz,
                onSelected:
                    enabled ? (_) => settings.setSampleRateOut(hz) : null,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final m in ['vpio', 'neural', 'none'])
              ChoiceChip(
                label: Text('AEC $m'),
                selected: settings.aecMethod == m,
                onSelected:
                    enabled ? (_) => settings.setAecMethod(m) : null,
              ),
          ],
        ),
      ],
    );
  }
}
