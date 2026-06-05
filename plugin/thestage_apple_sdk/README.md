# thestage_apple_sdk

Flutter plugin for the TheStage Apple SDK. On-device LLM, Whisper STT,
NeuTTS and VAD on iPhone/iPad, exposed as a typed Dart API over platform
channels. **iOS only** for now.

The plugin bundles the native `TheStageCore.xcframework`, so there's
nothing to build or link by hand — add the dependency and go.

## Install

1. **Add the dependency.** In your app's `pubspec.yaml`, point a `git:`
   dependency at the `plugin/thestage_apple_sdk` folder of this repo and
   pin a tag:

   ```yaml
   dependencies:
     thestage_apple_sdk:
       git:
         url: https://github.com/TheStageAI/AppleSDK.git
         path: plugin/thestage_apple_sdk
         ref: v1.0.0
   ```

2. **Enable SwiftPM** (the plugin ships as a Swift package):

   ```bash
   flutter config --enable-swift-package-manager
   ```

3. **Set the iOS deployment target to 18.0+.** In Xcode open
   `ios/Runner.xcodeproj`, select the **Runner** target → **General** →
   set **Minimum Deployments → iOS 18.0**. (Or set
   `IPHONEOS_DEPLOYMENT_TARGET = 18.0` in the build settings.)

4. **Fetch and run** on a physical device (the Simulator is not
   supported — MLX needs Metal on real hardware):

   ```bash
   flutter pub get
   flutter run --release -d <YOUR_IPHONE_DEVICE_ID>
   ```

That's it — no manual framework download or symlink. The xcframework is
vendored inside the plugin.

## Usage

```dart
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

// Validate the token once (then the SDK runs offline).
await TheStageFlutterSDK.initialize(api_token: 'th_…');

// Load a model straight from a HuggingFace repo id (cached after the
// first download).
await TheStageFlutterSDK.start_model(
  model_name: 'llm',
  engines_path: 'TheStageAI/Qwen3-0.6B',
);

final outputs = await TheStageFlutterSDK.infer(
  model_name: 'llm',
  input_json: {
    'prompt': 'Give me a one-line haiku about Swift.',
    'max_new_tokens': 64,
  },
);
print(outputs[0]['text']);

await TheStageFlutterSDK.stop_model(model_name: 'llm');
```

Other pipelines follow the same shape — pass `model_type` for TTS/VAD/STT:

```dart
await TheStageFlutterSDK.start_model(
  model_type: 'neutts',
  model_name: 'tts',
  engines_path: 'TheStageAI/neutts-multilingual',
);
```

For multi-module models, route each module to a compute device:

```dart
await TheStageFlutterSDK.start_model(
  model_type: 'wake_word',
  model_name: 'wake-word',
  engines_path: 'TheStageAI/wake-word',
  devices: {
    'melspectrogram': 'cpu',
    'embedding':      'npu',
    'wake_word':      'npu',
  },
);
```

## Audio playback

Streaming TTS plays through the bundled `TheStageAudioPlayer`. Drive it
at the pipeline's own sample rate (TTS output is 24 kHz):

```dart
final player = TheStageAudioPlayer();
await player.start(sample_rate: 24000);
await player.enqueue(samples);   // Float32List, mono, [-1.0, 1.0]
await player.drain();
await player.stop();
```

## API token

The SDK validates the token once on first model start, then runs
offline (7-day grace if the device briefly loses connectivity). Generate
yours at [app.thestage.ai](https://app.thestage.ai). Never hardcode it —
inject it at build time (see the example apps' `secrets.json` flow).

## Voice agent

For the full mic → VAD → STT → LLM → TTS loop with barge-in, use
`TheStageVoiceAgentFlutter`. See [`examples/voice_agent`](../../examples/voice_agent)
and [`docs/voice_agent.md`](../../docs/voice_agent.md).
