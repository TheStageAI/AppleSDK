#!/usr/bin/env python3
"""Encode a short reference clip into a NeuTTS multilingual ``voice_dir`` pack.

Public / minimal: uses only ``neucodec`` (HF ``neuphonic/neucodec``).
No talker weights and no TheStage Models.

Writes ``<out-dir>/voice.json`` for ``NeuTTSMultilingualPipeline`` /
``set_voice(voice_dir:)``.

::

    pip install -r requirements-neutts.txt

Example::

    python prepare_neutts_voice_pack.py \\
        --ref-audio ./dave.wav \\
        --ref-text "My name is Dave, and I am your virtual assistant." \\
        --language english \\
        --name dave \\
        --out-dir ./voices/dave

Reference audio is loaded at **16 kHz mono** (NeuCodec native). Prefer 3–10 s
of clean speech that matches ``--ref-text``.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--ref-audio", required=True, type=Path)
    p.add_argument("--ref-text", required=True)
    p.add_argument("--language", default="english")
    p.add_argument("--name", default=None)
    p.add_argument("--out-dir", required=True, type=Path)
    p.add_argument(
        "--codec-id",
        default="neuphonic/neucodec",
        help="HF id for NeuCodec.from_pretrained",
    )
    p.add_argument(
        "--temperature", type=float, default=1.0, help="Voice default sampling"
    )
    p.add_argument("--top-k", type=int, default=50)
    args = p.parse_args()

    if not args.ref_audio.is_file():
        raise SystemExit(f"missing --ref-audio: {args.ref_audio}")

    import torch
    from librosa import load
    from neucodec import NeuCodec

    print(f"loading codec {args.codec_id}…")
    codec = NeuCodec.from_pretrained(args.codec_id)
    codec.eval()

    wav, _ = load(str(args.ref_audio), sr=16000, mono=True)
    wav_tensor = torch.from_numpy(wav).float().unsqueeze(0).unsqueeze(0)
    with torch.no_grad():
        codes = codec.encode_code(audio_or_path=wav_tensor)
    ref_codes = codes.reshape(-1).int().tolist()

    voice = {
        "name": args.name or args.out_dir.name,
        "language": args.language.lower(),
        "ref_text": args.ref_text,
        "ref_codes": ref_codes,
        "temperature": args.temperature,
        "top_k": args.top_k,
        "min_new_tokens": 50,
        "use_lang_token": True,
    }

    args.out_dir.mkdir(parents=True, exist_ok=True)
    out = args.out_dir / "voice.json"
    out.write_text(json.dumps(voice, indent=2), encoding="utf-8")
    print(f"wrote {out}  codes={len(ref_codes)}  (~{len(ref_codes)/50:.1f}s @50Hz)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
