import 'package:flutter/material.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

import 'voice_chat_screen.dart';
import 'settings_model.dart';

// Secrets are injected at build/run time via:
//   flutter run --dart-define-from-file=../secrets.json
// See `test_apps/secrets.example.json` for the schema.
const _apiToken = String.fromEnvironment('TS_API_TOKEN');
const _openAIKey = String.fromEnvironment('OPENAI_API_KEY');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VoiceAgentApp());
}

class VoiceAgentApp extends StatelessWidget {
  const VoiceAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Voice Agent',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _agent = TheStageVoiceAgentFlutter();
  final _settings = VoiceAgentSettings();
  bool _initialized = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _agent.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    if (_apiToken.isEmpty) {
      setState(() {
        _initError =
            'TS_API_TOKEN not set.\n'
            'Run with: flutter run '
            '--dart-define-from-file=../secrets.json';
      });
      return;
    }
    if (_openAIKey.isEmpty) {
      setState(() {
        _initError =
            'OPENAI_API_KEY not set.\n'
            'Run with: flutter run '
            '--dart-define-from-file=../secrets.json';
      });
      return;
    }
    try {
      await TheStageFlutterSDK.initialize(api_token: _apiToken);
      setState(() => _initialized = true);
    } catch (e) {
      setState(() => _initError = 'SDK initialization failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              _initError!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (!_initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return VoiceChatScreen(
      agent: _agent,
      settings: _settings,
      openAIKey: _openAIKey,
    );
  }
}
