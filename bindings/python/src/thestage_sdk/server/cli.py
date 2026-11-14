"""``thestage-sdk``: the local server, and a one-shot transcriber.

    thestage-sdk serve --llm TheStageAI/Qwen3-0.6B --port 8000
    thestage-sdk transcribe meeting.m4a          # through a running server, else locally

The API token comes from ``THESTAGE_API_TOKEN`` (or ``--api-token``), the
Hugging Face token from ``HF_TOKEN`` when a repo needs one.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import sys
import urllib.error
import urllib.request
import uuid
from pathlib import Path

from aiohttp import web

from .. import initialize
from ..audio import ASRPipeline, TSAudioConfig, decode_audio
from .app import create_app
from .registry import SHIPPED_LLMS, ModelRegistry, ServerConfig

_LOCAL_HOSTS = {"127.0.0.1", "localhost", "::1"}


# ----------------------------------------------------------------------------------------
# Entry point
# ----------------------------------------------------------------------------------------
def main(argv: list[str] | None = None) -> int:
    """
    ``thestage-sdk serve`` or ``thestage-sdk transcribe``.

    Parameters
    ----------
    argv: list of str, optional
        Default is ``sys.argv[1:]``.

    Returns
    -------
    code: int
        The exit status.
    """
    parser = argparse.ArgumentParser(prog="thestage-sdk")
    commands = parser.add_subparsers(dest="command", required=True)
    _serve_arguments(
        commands.add_parser("serve", help="run the OpenAI-compatible server")
    )
    _transcribe_arguments(
        commands.add_parser("transcribe", help="print a file's transcript")
    )
    args = parser.parse_args(argv)
    if args.command == "serve":
        return serve(args)
    return asyncio.run(transcribe(args))


# ----------------------------------------------------------------------------------------
# serve
# ----------------------------------------------------------------------------------------
def _model(value: str) -> str | None:
    """
    Parameters
    ----------
    value: str
        A repo id, or ``none``.

    Returns
    -------
    name: str or None
    """
    return None if value.lower() == "none" else value


def _models(value: str) -> list[str]:
    """
    Parameters
    ----------
    value: str
        Comma-separated repo ids, ``all`` (the shipped chat models) or ``none``.

    Returns
    -------
    names: list of str
        The default first.
    """
    if value.lower() == "all":
        return list(SHIPPED_LLMS)
    return [name.strip() for name in value.split(",") if _model(name.strip())]


def _serve_arguments(p: argparse.ArgumentParser) -> None:
    """
    Parameters
    ----------
    p: argparse.ArgumentParser
    """
    defaults = ServerConfig()
    p.add_argument(
        "--llm",
        type=_models,
        default=[defaults.llm],
        help="chat models, comma-separated (the first is the default), all, or none",
    )
    p.add_argument(
        "--vlm", type=_model, default=defaults.vlm, help="vision model for images"
    )
    p.add_argument("--asr", type=_model, default=defaults.asr, help="speech recognition")
    p.add_argument("--tts", type=_model, default=defaults.tts, help="speech synthesis")
    p.add_argument("--voice", default=defaults.voice, help="default TTS voice")
    p.add_argument(
        "--tts-language", default=None, help="TTS language (NeuTTS multilingual)"
    )
    p.add_argument("--vad", type=_model, default=defaults.vad, help="VAD for file cuts")
    p.add_argument(
        "--streaming-algorithm",
        choices=["THESTAGE_V5_5", "THESTAGE_V5", "THESTAGE_V6", "NAIVE", "pack"],
        default=defaults.streaming_algorithm,
        help="realtime commit policy (pack: the recogniser pack's own)",
    )
    p.add_argument(
        "--turn-detector",
        default=defaults.turn_detector,
        help="realtime turn detector repo, or none to end turns on silence",
    )
    p.add_argument(
        "--aec",
        choices=["webrtc", "vpio", "neural", "none"],
        help="canceller for realtime sessions that capture the Mac's microphone",
    )
    p.add_argument(
        "--only-configured-models",
        dest="allow_any_model",
        action="store_false",
        help="refuse requests that name another TheStageAI repo",
    )
    p.add_argument(
        "--allow-local-images",
        action="store_true",
        help="accept chat image_url parts that name a file on this machine",
    )
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=8000)
    p.add_argument("--api-key", default=os.environ.get("THESTAGE_SERVER_API_KEY"))
    p.add_argument("--api-token", default=os.environ.get("THESTAGE_API_TOKEN"))
    p.add_argument(
        "--preload", action="store_true", help="load every model before serving"
    )
    p.add_argument("--log-level", default="INFO")


def serve(args: argparse.Namespace) -> int:
    """
    Run the server until interrupted.

    Parameters
    ----------
    args: argparse.Namespace

    Returns
    -------
    code: int
        2 without a token, with a network host and no ``--api-key``, or with V5.5
        and no turn detector.
    """
    logging.basicConfig(
        level=args.log_level, format="%(asctime)s %(levelname)s %(message)s"
    )
    if not args.api_token:
        print("set THESTAGE_API_TOKEN or pass --api-token", file=sys.stderr)
        return 2

    if args.host not in _LOCAL_HOSTS and not args.api_key:
        print(
            f"--host {args.host} is reachable from the network: set --api-key",
            file=sys.stderr,
        )
        return 2

    if args.streaming_algorithm == "THESTAGE_V5_5" and args.turn_detector == "none":
        print(
            "--streaming-algorithm THESTAGE_V5_5 needs a --turn-detector", file=sys.stderr
        )
        return 2

    config = ServerConfig(
        llm=args.llm[0] if args.llm else None,
        llm_choices=args.llm[1:],
        vlm=args.vlm,
        asr=args.asr,
        tts=args.tts,
        voice=args.voice,
        tts_language=args.tts_language,
        vad=args.vad,
        streaming_algorithm=None
        if args.streaming_algorithm == "pack"
        else args.streaming_algorithm,
        turn_detector=None if args.turn_detector == "none" else args.turn_detector,
        audio=TSAudioConfig(aec=args.aec),
        api_key=args.api_key,
        allow_any_model=args.allow_any_model,
        allow_local_images=args.allow_local_images,
    )

    async def application() -> web.Application:
        await initialize(api_token=args.api_token, hf_token=os.environ.get("HF_TOKEN"))
        registry = ModelRegistry(config)
        if args.preload:
            await registry.preload()
        return create_app(config, registry)

    print(f"thestage-sdk: OpenAI-compatible API at http://{args.host}:{args.port}/v1")
    web.run_app(application(), host=args.host, port=args.port, print=None)
    return 0


# ----------------------------------------------------------------------------------------
# transcribe
# ----------------------------------------------------------------------------------------
def _transcribe_arguments(p: argparse.ArgumentParser) -> None:
    """
    Parameters
    ----------
    p: argparse.ArgumentParser
    """
    p.add_argument("file")
    p.add_argument(
        "--url", default=os.environ.get("THESTAGE_SERVER_URL", "http://127.0.0.1:8000")
    )
    p.add_argument("--language", default="auto")
    p.add_argument("--model", default="TheStageAI/thewhisper-large-v3-turbo")
    p.add_argument("--api-key", default=os.environ.get("THESTAGE_SERVER_API_KEY"))
    p.add_argument("--api-token", default=os.environ.get("THESTAGE_API_TOKEN"))


async def transcribe(args: argparse.Namespace) -> int:
    """
    Print a file's transcript: through the running server at ``--url`` when there
    is one, otherwise by loading the recogniser here.

    Parameters
    ----------
    args: argparse.Namespace

    Returns
    -------
    code: int
    """
    path = Path(args.file)
    data = path.read_bytes()
    try:
        text = await asyncio.to_thread(_post_transcription, args, path.name, data)
    except (urllib.error.URLError, ConnectionError):
        if not args.api_token:
            print(
                "no server at --url and no THESTAGE_API_TOKEN to run locally",
                file=sys.stderr,
            )
            return 2
        await initialize(api_token=args.api_token, hf_token=os.environ.get("HF_TOKEN"))
        asr = await ASRPipeline.load(args.model)
        audio = await decode_audio(data, format=path.suffix.lstrip(".") or None)
        text = (await asr.infer(audio, language=args.language)).text.strip()
    print(text)
    return 0


def _post_transcription(args: argparse.Namespace, name: str, data: bytes) -> str:
    """
    multipart/form-data with the standard library (no client dependency).

    Parameters
    ----------
    args: argparse.Namespace
    name: str
        The file name sent.
    data: bytes
        The file.

    Returns
    -------
    text: str
    """
    boundary = uuid.uuid4().hex
    fields = {"model": args.model, "language": args.language, "response_format": "json"}

    def part(disposition: str, content_type: str = "") -> bytes:
        head = f"--{boundary}\r\nContent-Disposition: form-data; {disposition}\r\n"
        return (head + content_type + "\r\n").encode()

    body = b"".join(part(f'name="{k}"') + f"{v}\r\n".encode() for k, v in fields.items())
    body += part(
        f'name="file"; filename="{name}"', "Content-Type: application/octet-stream\r\n"
    )
    body += data + f"\r\n--{boundary}--\r\n".encode()
    request = urllib.request.Request(
        args.url.rstrip("/") + "/v1/audio/transcriptions",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    if args.api_key:
        request.add_header("Authorization", f"Bearer {args.api_key}")
    with urllib.request.urlopen(request, timeout=600) as response:
        return json.loads(response.read())["text"]


if __name__ == "__main__":
    sys.exit(main())
