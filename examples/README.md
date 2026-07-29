# Examples (Apple SDK 1.1.0)

All examples in this folder target **TheStage Apple SDK 1.1.0**.

| Example | Platform | Notes |
| --- | --- | --- |
| [`macos_swift_tts/`](./macos_swift_tts/) | macOS 15+ | Fastest path — `swift run`, HF NeuTTS |
| [`engine_bench/`](./engine_bench/) | iPhone iOS 18+ | LLM / TTS / ASR benches from Hugging Face |
| [`tts_front_stream/`](./tts_front_stream/) | iPhone (Flutter) | Streaming TTS UI |
| [`voice_agent/`](./voice_agent/) | iPhone (Flutter) | Full mic → VAD → STT → LLM → TTS agent |

Each example has its own `VERSION` file matching this SDK line. Pin the
SDK to tag `1.1.0` (see each README).
