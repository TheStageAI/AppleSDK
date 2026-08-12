# Prepare TTS voice packs (public, minimal)

Encode a **reference WAV + transcript** into a `voice_dir` (`voice.json`)
for Apple SDK TTS. **No TheStage Models / private repos** — only public
PyPI packages and Hugging Face codec / Base weights.

| Script | Apple SDK pipeline | Public encode API |
|---|---|---|
| `prepare_qwen3_voice_pack.py` | `Qwen3TTSPipeline` | `qwen_tts.Qwen3TTSModel.create_voice_clone_prompt` |
| `prepare_neutts_voice_pack.py` | `NeuTTSMultilingualPipeline` | `neucodec.NeuCodec.encode_code` |

Point `voice_dir:` / `set_voice(voice_dir:)` at the output folder.

## Setup

```bash
python3 -m venv .venv && source .venv/bin/activate

# Qwen3 pack (uses Qwen/Qwen3-TTS-12Hz-0.6B-Base for encode only)
pip install -r requirements-qwen3.txt

# NeuTTS pack (uses neuphonic/neucodec only — no talker weights)
pip install -r requirements-neutts.txt
```

## Qwen3-TTS

```bash
python prepare_qwen3_voice_pack.py \
  --ref-audio ./my_en.wav \
  --ref-text "We still have time to practice clear speech." \
  --language english \
  --name tutor_en \
  --out-dir ./VoicePacks/tutor_en
```

One pack per language for mixed-language tutors (`examples/tutor_tts`).

## NeuTTS multilingual

```bash
python prepare_neutts_voice_pack.py \
  --ref-audio ./dave.wav \
  --ref-text "My name is Dave, and I am your virtual assistant." \
  --language english \
  --name dave \
  --out-dir ./voices/dave
```

## Tips

- Keep references short and clean (Qwen ~2–4 s; NeuTTS ~3–10 s).
- `--ref-text` must match the WAV.
- Ready-made tutor packs: `TheStageAI/Qwen3-TTS-Tutor-VoicePacks`.
