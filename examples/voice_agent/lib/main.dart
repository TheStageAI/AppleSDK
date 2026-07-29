import 'package:flutter/material.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

import 'backend/settings_model.dart';
import 'ui/app_theme.dart';
import 'ui/voice_chat_screen.dart';

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
      theme: buildVoiceAgentTheme(brightness: Brightness.light),
      darkTheme: buildVoiceAgentTheme(brightness: Brightness.dark),
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
    // Cloud LLM needs OPENAI_API_KEY; on-device local (HF or BundledModels) does not.
    final needsCloudKey = _settings.llmProvider != 'local';
    if (needsCloudKey && _openAIKey.isEmpty) {
      setState(() {
        _initError =
            'OPENAI_API_KEY not set.\n'
            'Run with: flutter run '
            '--dart-define-from-file=../secrets.json\n'
            '(or set llmProvider=local for on-device HF / BundledModels).';
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
              style: const TextStyle(
                color: AppColors.systemRed,
                fontSize: 16,
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (!_initialized) {
      return const Scaffold(
        body: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    return VoiceChatScreen(
      agent: _agent,
      settings: _settings,
      openAIKey: _openAIKey,
    );
  }
}
