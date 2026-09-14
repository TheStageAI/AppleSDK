#!/usr/bin/env python3
"""Encode a short reference clip into a Qwen3-TTS ``voice_dir`` pack.

Public / minimal: uses only the official ``qwen-tts`` package and the
HF Base weights for ``create_voice_clone_prompt``. No TheStage Models.

Writes ``<out-dir>/voice.json`` for ``Qwen3TTSPipeline`` /
``set_voice(voice_dir:)`` (same shape as the tutor packs).

::

    pip install -r requirements-qwen3.txt

Example::

    python prepare_qwen3_voice_pack.py \\
        --ref-audio ./tutor_en.wav \\
        --ref-text "We still have time to practice clear speech." \\
        --language english \\
        --name tutor_en \\
        --out-dir ./VoicePacks/tutor_en

Tip: keep the reference ~2–4 s of clean speech that matches ``--ref-text``.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--ref-audio", required=True, type=Path)
    p.add_argument("--ref-text", required=True)
    p.add_argument(
        "--language",
        default="english",
        help="Qwen language name (english, spanish, french, …)",
    )
    p.add_argument("--name", default=None, help="voice.json name field")
    p.add_argument("--out-dir", required=True, type=Path)
    p.add_argument(
        "--model-id",
        default="Qwen/Qwen3-TTS-12Hz-0.6B-Base",
        help="HF id used only for create_voice_clone_prompt (codec encode)",
    )
    p.add_argument(
        "--device-map",
        default="cpu",
        help="Passed to Qwen3TTSModel.from_pretrained (cpu / mps / cuda)",
    )
    args = p.parse_args()

    if not args.ref_audio.is_file():
        raise SystemExit(f"missing --ref-audio: {args.ref_audio}")

    from qwen_tts import Qwen3TTSModel

    print(f"loading {args.model_id} ({args.device_map})…")
    model = Qwen3TTSModel.from_pretrained(
        args.model_id, device_map=args.device_map
    )
    items = model.create_voice_clone_prompt(
        ref_audio=str(args.ref_audio),
        ref_text=args.ref_text,
        x_vector_only_mode=False,
    )
    it = items[0]
    codes = it.ref_code.detach().cpu().numpy().astype(int)
    spk = it.ref_spk_embedding.detach().float().cpu().numpy().reshape(-1)

    # Legacy Qwen dialect: frame-major [T][num_codebooks] — same as tutor packs.
    voice = {
        "name": args.name or args.out_dir.name,
        "language": args.language.lower(),
        "ref_text": args.ref_text,
        "ref_codes": codes.tolist(),
        "spk_embedding": [float(x) for x in spk],
    }

    args.out_dir.mkdir(parents=True, exist_ok=True)
    out = args.out_dir / "voice.json"
    out.write_text(json.dumps(voice, indent=2), encoding="utf-8")
    print(
        f"wrote {out}  frames={codes.shape[0]}  "
        f"codebooks={codes.shape[1] if codes.ndim == 2 else 1}  "
        f"spk_dim={len(spk)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
