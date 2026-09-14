# Examples (Apple SDK 1.4.0)

All examples in this folder target **TheStage Apple SDK 1.4.0**.

| Example | Platform | Notes |
| --- | --- | --- |
| [`macos_swift_tts/`](./macos_swift_tts/) | macOS 15+ | Fastest path — `swift run`, HF NeuTTS |
| [`tutor_small_llms/`](./tutor_small_llms/) | macOS 15+ | Five small-LLM tutorial guides — `swift run` |
| [`engine_bench/`](./engine_bench/) | iPhone iOS 18+ | LLM / TTS / ASR / VLM benches from Hugging Face |
| [`tutor_tts/`](./tutor_tts/) | iPhone iOS 18+ | Mixed-language Qwen3-TTS (`set_voice` per `<en>`/`<es>` span) |
| [`voice_agent/`](./voice_agent/) | iPhone (Flutter) | Full mic → VAD → STT → LLM → TTS agent |
| [`voice_agent_custom_nodes/`](./voice_agent_custom_nodes/) | iPhone (Flutter) | Custom nodes, VLM captions, ModelRoster |

Each example has its own `VERSION` file matching this SDK line. Pin the
SDK to tag `1.4.0` (see each README).
