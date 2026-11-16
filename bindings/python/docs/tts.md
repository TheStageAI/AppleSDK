# Text to speech

[Docs home](README.md) · [Language models](llm.md) · [Vision](vlm.md) ·
[Speech recognition](asr.md) · [Microphone and audio](audio.md) ·
[Voice agent](voice_agent.md) · [Server](server.md)

```python
import thestage_sdk as ts

tts = await ts.TTSPipeline.load(
    "TheStageAI/neutts-nano-multilingual",
    voice_id="dave",           # a voice that ships with the model: "dave", "paul", "jo"
    language="english",        # multilingual models: the text's language
    device="npu",              # "npu" (default), "gpu" or "cpu"
)
tts.sample_rate                # Hz of the audio it returns
await tts.set_voice("jo", language="english")   # switch voice without reloading
```

`config` (every call, all optional):

| Key | Type | Meaning |
|---|---|---|
| `temperature` | float | Variation in delivery; lower is steadier |
| `top_k` | int | Sampling filter |
| `seed` | int | The same audio for the same text |
| `sample_rate_out` | int | Resample the output to this rate (Hz) |

## Whole clip

```python
result = await tts.infer("Hello from your Mac.", config={"seed": 7})
result.samples        # float32 NumPy array, mono
result.sample_rate    # Hz
result.duration       # seconds of audio
result.rtf            # speed: seconds of audio per second of compute
```

## Streaming

Send text as it arrives (for example from a language model) and read audio as soon as
each piece is synthesized:

```python
stream = await tts.open_stream(config=None)
stream.sample_rate                       # Hz of the chunks

async def feed():
    async for chunk in llm.infer_stream("Tell me about the Moon in three sentences."):
        if not chunk.is_final:
            await stream.send(chunk.text)
    await stream.close()                 # no more text; the rest of the audio follows

feeding = asyncio.create_task(feed())
async for audio in stream:               # float32 NumPy arrays at stream.sample_rate
    play(audio)
await feeding
```

| Method | What it does |
|---|---|
| `send(text)` | Add text; its audio follows on the iterator |
| `close()` | No more text: the rest is spoken, then the iterator ends |
| `cancel()` | Drop the text and audio not yet delivered; the iterator ends |

Playing and saving the arrays: [Microphone and audio → Playing audio](audio.md#playing-audio-from-python).
A spoken conversation with interruption and echo cancellation is the
[voice agent](voice_agent.md), which plays audio itself.

## Runnable examples

- [`examples/tts_speak.py`](../examples/tts_speak.py): a whole clip and a sentence-by-sentence stream to WAV files
- [`examples/tts_play.py`](../examples/tts_play.py): a language model's answer spoken through the speakers as it is written
