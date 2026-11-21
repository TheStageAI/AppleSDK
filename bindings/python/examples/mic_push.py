"""Live captions from a microphone you choose: sounddevice captures, the engine listens.

pip install sounddevice
python examples/mic_push.py --list             # the input devices
python examples/mic_push.py --device "USB"     # a device by (part of) its name or index

The SDK's own capture (source="microphone") always uses the macOS default input; this is
how to use another one, or any audio you produce yourself.
"""

import argparse
import asyncio

import sounddevice as sd
from _common import initialize

import thestage_sdk as ts

RATE, BLOCK = 16_000, 1_600  # 100 ms blocks


async def print_turns(turns) -> None:
    async for turn in turns:
        line = f"{turn.committed} \033[2m{turn.hypothesis}\033[0m"
        print("\r\033[K" + line, end="\n" if turn.end_of_turn else "", flush=True)


async def main(device) -> None:
    await initialize()
    engine = await ts.ASREngine.create(
        ts.TSAgentConfig(
            turn_detector="TheStageAI/smart-turn-v3",
            asr_streaming_config=ts.ASRStreamingConfig(algorithm="THESTAGE_V5_5"),
            audio=ts.TSAudioConfig(source="push"),
        )
    )
    printer = asyncio.create_task(print_turns(await engine.turns()))
    await engine.start()

    loop = asyncio.get_running_loop()
    blocks: asyncio.Queue = asyncio.Queue()

    def on_audio(indata, frames, time, status) -> None:  # sounddevice's thread
        loop.call_soon_threadsafe(blocks.put_nowait, indata[:, 0].copy())

    stream = sd.InputStream(
        device=device,
        channels=1,
        samplerate=RATE,
        dtype="float32",
        blocksize=BLOCK,
        callback=on_audio,
    )
    print(f"listening on {sd.query_devices(stream.device)['name']} (Ctrl-C to stop)")
    try:
        with stream:
            while True:
                await engine.push(await blocks.get(), sample_rate=RATE)
    finally:
        await engine.stop()
        await printer


parser = argparse.ArgumentParser()
parser.add_argument("--device", help="input device name (or part of it) or index")
parser.add_argument("--list", action="store_true", help="list the devices and exit")
args = parser.parse_args()
if args.list:
    print(sd.query_devices())
else:
    device = int(args.device) if args.device and args.device.isdigit() else args.device
    try:
        asyncio.run(main(device))
    except KeyboardInterrupt:
        pass
