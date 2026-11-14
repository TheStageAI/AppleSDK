"""Live transcription on V5.5: the Mac's microphone, its system audio, both, or a pushed
WAV, optionally with speakers named from a saved-voices database.

python examples/asr_engine_live.py                    # microphone, Ctrl-C to stop
python examples/asr_engine_live.py --source meeting   # system audio + microphone
python examples/asr_engine_live.py --source system    # only what the Mac plays
python examples/asr_engine_live.py --aec none         # microphone without a canceller
python examples/asr_engine_live.py speech.wav         # push a file at real time
python examples/asr_engine_live.py --speakers         # names from speakers.json
python examples/asr_engine_live.py --speakers --enroll Kirill=me.wav  # add a voice
python examples/asr_engine_live.py --speakers --save Mira  # save the main unnamed voice

System and meeting capture need macOS 14.2+ and the Screen & System Audio Recording
permission for the terminal you run this from.
"""

import argparse
import asyncio

from _common import initialize
from asr_file import load_wav_16k

import thestage_sdk as ts


async def print_turns(engine: ts.ASREngine, last: list) -> None:
    async for turn in await engine.turns():
        names = {s.id: s.name or s.id for s in turn.speakers}
        who = (
            f"{names.get(turn.speaker_id, turn.speaker_id)}: " if turn.speaker_id else ""
        )
        text = turn.transcript if turn.end_of_turn else turn.committed
        line = f"{who}{text} \033[2m{'' if turn.end_of_turn else turn.hypothesis}\033[0m"
        print("\r\033[K" + line, end="\n" if turn.end_of_turn else "", flush=True)
        last[:] = turn.speakers


async def enroll(db: str, entries: list[str]) -> list[ts.SpeakerProfile]:
    profiles = ts.SpeakerProfile.load_all(db)
    if not entries:
        return profiles
    identifier = await ts.SpeakerIDPipeline.load("TheStageAI/speaker-id-v2")
    for entry in entries:
        name, wav = entry.split("=", 1)
        profiles = [p for p in profiles if p.id != name]
        profiles.append(await identifier.enroll(load_wav_16k(wav), id=name, name=name))
        print(f"enrolled {name} from {wav}")
    ts.SpeakerProfile.save_all(db, profiles)
    return profiles


async def main(args: argparse.Namespace) -> None:
    await initialize()
    wav = args.wav
    profiles = await enroll(args.db, args.enroll) if args.speakers else []
    config = ts.TSAgentConfig(
        stt="TheStageAI/thewhisper-large-v3-turbo",
        vad="TheStageAI/silero-vad",
        turn_detector="TheStageAI/smart-turn-v3",  # V5.5 ends turns with SmartTurn
        language="auto",
        timestamps="WORD",
        turn_end_mode=None,  # V5.5 picks "dnn"
        turn_eot_threshold=None,  # V5.5: 0.95
        turn_pause_trigger_ms=None,  # SDK default: 256
        asr_streaming_config=ts.ASRStreamingConfig(algorithm="THESTAGE_V5_5"),
        speakers=ts.ASRSpeakerConfig(
            diarization="TheStageAI/Nemotron-3-Diarization",
            identification="TheStageAI/speaker-id-v2",  # None: labels without names
            identity=ts.SpeakerIDConfig(enrolled=profiles),
        )
        if args.speakers
        else None,
        audio=ts.TSAudioConfig(source="push" if wav else args.source, aec=args.aec),
    )
    engine = await ts.ASREngine.create(config)
    speakers: list[ts.ASRSpeaker] = []
    printer = asyncio.create_task(print_turns(engine, speakers))  # subscribe before start
    await engine.start()
    try:
        if wav:
            audio, step = load_wav_16k(wav), 1_600  # 100 ms
            for i in range(0, len(audio), step):
                await engine.push(audio[i : i + step])
                await asyncio.sleep(0.1)
        else:
            await asyncio.Event().wait()
    finally:
        await engine.stop()
        await printer
        if args.save:
            unnamed = [s for s in speakers if s.name is None and s.embedding is not None]
            if unnamed:
                voice = max(unnamed, key=lambda s: s.speech_seconds)
                profiles = [p for p in profiles if p.id != args.save]
                profiles.append(voice.profile(name=args.save))
                ts.SpeakerProfile.save_all(args.db, profiles)
                print(f"saved {voice.id} ({voice.speech_seconds:.0f} s) as {args.save}")


parser = argparse.ArgumentParser()
parser.add_argument("wav", nargs="?", help="push this WAV instead of capturing")
parser.add_argument(
    "--source", default="microphone", choices=["microphone", "system", "meeting"]
)
parser.add_argument("--aec", choices=["webrtc", "vpio", "neural", "none"])
parser.add_argument("--speakers", action="store_true", help="label and name speakers")
parser.add_argument("--db", default="speakers.json", help="the saved-voices database")
parser.add_argument(
    "--enroll", action="append", default=[], metavar="NAME=WAV", help="add a saved voice"
)
parser.add_argument(
    "--save", metavar="NAME", help="save the main unnamed voice at the end"
)
try:
    asyncio.run(main(parser.parse_args()))
except KeyboardInterrupt:
    pass
