# Benchmarks

On-device performance for TheStage Apple SDK pipelines. Numbers below are from
**release** builds on **Apple M2 Max (NPU / ANE), macOS 26.2**, measured
2026-07-28. Use them as guidance for relative speed and footprint — not as an
SLA. Results move with chip, OS, thermals, and bundle revision.

Debug builds are much slower; always measure release.

## Metric definitions

| Metric | Meaning |
|---|---|
| **TTFT** | Prefill time to first token (LLM / ASR decoder) |
| **TTFA** | Streaming time-to-first-audio (TTS) |
| **tok/s** | Steady-state decode rate after warmup |
| **rtf / rtfx** | `audio_seconds / wall_seconds` (>1 = faster than realtime) |
| **mem (MB)** | Process footprint after the measured window |

## LLM (warmed, 256 new tokens, NPU)

Decode tok/s is nearly flat across prompt length; **TTFT** grows with prefill
size (small → medium → long suite prompts).

| Model | HF repo | tok/s (medium) | TTFT small → long (s) | mem (MB, medium) |
|---|---|---:|---:|---:|
| Qwen3-0.6B | `TheStageAI/Qwen3-0.6B` | 58.5 | 0.063 → 0.158 | 271 |
| Gemma3-1B | `TheStageAI/Gemma3-1B` | 83.1 | 0.058 → 0.112 | 163 |
| LFM2.5-230M | `TheStageAI/LFM2.5-230M` | 252 | 0.039 → 0.053 | 52 |
| LFM2.5-350M | `TheStageAI/LFM2.5-350M` | 178 | 0.038 → 0.060 | 61 |

## TTS (warmed, NPU)

| Bundle | HF repo | Batch rtf | Stream rtfx | TTFA (s) | mem (MB) |
|---|---|---:|---:|---:|---:|
| NeuTTS nano multilingual | `TheStageAI/neutts-nano-multilingual` | 2.66 | 2.95 | 0.36 | ~215 |
| Qwen3-TTS 12 Hz 0.6B | `TheStageAI/Qwen3-TTS-12Hz-0.6B-Base` | 1.76 | 2.18 | 0.30 | ~423 |

Output is **24 kHz** mono. Qwen3-TTS benches use official sampling defaults
with a frame cap for stable runs.

## ASR (warmed, NPU)

Primary shipping STT is Whisper. Qwen3-ASR is listed for comparison.

| Bundle | HF repo | Audio | rtfx | decode tok/s | mem (MB) |
|---|---|---|---:|---:|---:|
| thewhisper-large-v3-turbo | `TheStageAI/thewhisper-large-v3-turbo` | ~2.6 s (`say` fox sentence) | 16.7 | 233 | ~96 |
| Qwen3-ASR 0.6B | `TheStageAI/qwen3-asr-0.6b` | 8.88 s fixture | 13.9 | 39.6 | ~342 |

Input is **16 kHz** mono. Whisper shipping windows are **10 s**.

## Agent checklist

- Quote device class + release build when citing numbers.
- LLM: report tok/s **and** TTFT; they answer different questions.
- TTS: prefer stream **rtfx / TTFA** for voice-agent UX; batch **rtf** for offline synth.
- ASR: prefer **rtfx** for realtime; tok/s is decoder throughput only.
