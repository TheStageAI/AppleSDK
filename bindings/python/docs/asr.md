# Speech recognition

[Docs home](README.md) · [Language models](llm.md) · [Vision](vlm.md) ·
[Microphone and audio](audio.md) · [Text to speech](tts.md) · [Voice agent](voice_agent.md) ·
[Server](server.md)

| You have | Use |
|---|---|
| A recording (file, bytes, array) | `ASRPipeline`: one call, or a stream of partial results |
| Live audio (microphone, system audio, a stream you push) | `ASREngine`: turns as people speak |

Recognisers: `TheStageAI/thewhisper-large-v3-turbo` (99 languages, default),
`TheStageAI/parakeet-tdt-0.6b-v3` (25 European languages),
`TheStageAI/Qwen3-ASR-0.6B`.

## Recordings: `ASRPipeline`

```python
import thestage_sdk as ts

asr = await ts.ASRPipeline.load(
    "TheStageAI/thewhisper-large-v3-turbo",
    model_name=None,               # the name to unload it by; default: the repo id
    device="npu",                  # "npu" (default), "gpu" or "cpu"
    vad="TheStageAI/silero-vad",   # cuts long audio in silence; None: fixed-length windows
)
asr.sample_rate                    # 16000: what infer expects

audio = await ts.decode_audio(open("interview.m4a", "rb").read(), sample_rate=16_000,
                              format="m4a")      # or any 1-D float32 array at 16 kHz
result = await asr.infer(
    audio,
    language="auto",               # "auto" or a code: "en", "de", "fr", …
    timestamps="WORD",             # "WORD" or "NONE"
)
result.text                        # the transcript
result.language                    # detected or given language code
for word in result.words:          # with timestamps="WORD"
    print(f"{word.t0:6.2f}–{word.t1:6.2f}  {word.text}")
```

`ASRWord`: `text`, `t0` and `t1` (seconds from the start), `is_final`, `speaker_id`,
`confidence`.

**Progress on long recordings.** `infer_stream` reports the transcript window by window;
each partial's text only grows, and the last item equals what `infer` returns:

```python
async for result, is_final in asr.infer_stream(audio, language="auto", timestamps="WORD"):
    print(("" if is_final else "… ") + result.text)
```

## Live audio: `ASREngine`

The engine listens continuously and splits speech into **turns** (one person's
utterance, ended when they sound finished or after a pause). Each turn updates as words
are recognised.

```python
config = ts.TSAgentConfig(
    stt="TheStageAI/thewhisper-large-v3-turbo",  # recogniser
    vad="TheStageAI/silero-vad",                 # voice activity detector
    turn_detector="TheStageAI/smart-turn-v3",    # turn model; V5.5 needs it
    language="auto",                             # "auto" or a code
    timestamps="WORD",                           # "WORD" or "NONE"
    turn_end_mode=None,           # "vad" | "dnn" | "none"; None: V5.5 picks "dnn"
    turn_eot_threshold=None,      # turn model's end-of-turn threshold; V5.5: 0.95
    turn_pause_trigger_ms=None,   # pause (ms) before the turn model is asked; 256
    asr_streaming_config=ts.ASRStreamingConfig(algorithm="THESTAGE_V5_5"),
    speakers=None,                # ts.ASRSpeakerConfig(...): who spoke (below)
    audio=ts.TSAudioConfig(source="microphone"),  # see Microphone and audio
)
engine = await ts.ASREngine.create(config)

turns = await engine.turns()       # subscribe BEFORE start: turns are not replayed
await engine.start()               # capture starts; a permission prompt may appear
try:
    async for turn in turns:
        print(turn.committed, "|", turn.hypothesis)
        if turn.end_of_turn:
            handle(turn.transcript)
finally:
    await engine.stop()            # the open turn ends; the iterator finishes
```

A field left `None` keeps the SDK's default.

**Commit policy** (`asr_streaming_config.algorithm`):

| Value | Behaviour |
|---|---|
| `"THESTAGE_V5_5"` | Recommended. Words commit after 0.75 s of audio and three agreeing passes; a reverberant room keeps the sentence open; the turn model ends the turn when the speaker sounds finished. Needs `turn_detector` |
| `"THESTAGE_V5"` | The same commits, turns end after a silence |
| `None` | The recogniser pack's own policy |

Every update of a turn is a full `ASRTurn`, not a diff. The names follow AssemblyAI's
Universal-Streaming turns:

| Field | Meaning |
|---|---|
| `turn_order` | Which turn this is, in order |
| `transcript` | The turn's text; punctuated and cased on the last update |
| `utterance` | The finished sentence(s), for an assistant to act on |
| `committed` | Final text so far. Only grows within a turn: safe to act on |
| `hypothesis` | The live tail after `committed`. May change: show it, don't act on it |
| `end_of_turn` | True on the turn's last update |
| `turn_is_formatted` | True when `transcript` is punctuated and cased |
| `end_of_turn_confidence` | The turn model's confidence that the turn ended, when it decided |
| `words` | `ASRWord`s with timestamps; `is_final` marks committed words; `speaker_id` with speakers |
| `language` | Language code. With `language="auto"` it is `None` until the session has heard about 10 s of speech and detected once; from then on every turn carries the detected code, and turns that ended before the detection are re-emitted, transcribed again in it |
| `speaker_id`, `speakers` | With speakers: the turn's speaker and the session's `ASRSpeaker`s |
| `speaker_revision` | Grows when speaker labels or names change |

A live caption that rewrites its line, then moves on when the turn ends:

```python
async for turn in turns:
    line = f"{turn.committed} \033[2m{turn.hypothesis}\033[0m"     # hypothesis dimmed
    print("\r\033[K" + line, end="\n" if turn.end_of_turn else "", flush=True)
```

**Where the audio comes from** is `config.audio`: the default microphone, the Mac's
system audio, both (`meeting`), or samples you `push`. Device choice, permissions and
echo cancellation: [Microphone and audio](audio.md).

### Who spoke: speakers and saved voices

`speakers=ts.ASRSpeakerConfig(...)` labels every word with a speaker and names speakers
whose voice matches a saved one.

```python
profiles = ts.SpeakerProfile.load_all("speakers.json")   # [] when the file is new

config.speakers = ts.ASRSpeakerConfig(
    diarization="TheStageAI/Nemotron-3-Diarization",     # who speaks when
    identification="TheStageAI/speaker-id-v2",           # None: labels without names
    identity=ts.SpeakerIDConfig(enrolled=profiles),      # saved voices
)
```

`SpeakerIDConfig` also carries the thresholds and the three live rules. Every field left
`None` keeps the SDK's value; a rule left `None` is off, and `ts.SpeakerEvidenceConfig()`
(or any of the three with no arguments) turns that rule on at the SDK's measured
defaults.

```python
identity = ts.SpeakerIDConfig(
    enrolled=profiles,
    identity_threshold=0.55,        # a speaker takes its best saved voice at >= this cosine
    identity_neg_threshold=0.35,    # and keeps the name while the score stays above this
    identity_margin=0.10,           # how far the best saved voice must lead the second
    min_identity_speech_s=2.0,      # speech a label needs before it is matched
    update_speech_s=2.0,            # speech between later matches of a label
    rejoin_threshold=0.45,          # a new label joins a speaker nobody owns at >= this
    voice_change=ts.SpeakerVoiceChangeConfig(   # split a label where its voice changes
        piece_s=2.0, hop_s=0.25, voice_delay_s=30, threshold=0.30, run_s=2.0),
    long_turn_merge=ts.SpeakerLongTurnMergeConfig(  # one person under two speakers
        min_turn_s=8, threshold=0.80),
    evidence=ts.SpeakerEvidenceConfig(          # what counts as a speaker's voice
        turn_evidence=True,             # a turn pinned to a speaker is its evidence
        new_speaker_min_turn_s=6,       # a turn opens a new speaker only with >= 6 s
        turn_born=True,                 # False: only the diarizer adds people
        skip_overlap=True),             # evidence leaves out moments of crosstalk
)
```

| Rule | What it fixes | On the dev sets (DER, AMI shown-count error) |
|---|---|---|
| `voice_change` | A cold streaming diarizer keeps a second voice under the first label; the split cuts the label at the pause where the voice changed | AMI 30.47 → 30.14 |
| `long_turn_merge` | The diarizer gave one person two labels; a long turn that matches the other speaker folds them | AMI 30.47 → 30.14, vox +0.2 |
| `evidence` | A short turn of a known voice opened a new speaker (three people shown as four); turn-born speakers never grew past a 3 s seed | vox 11.87 → 11.47, AMI 30.14 → 29.84, count error 2.44 → 0.67 |

The three are independent; the Notes apps run all of them.

Each `ASRSpeaker` in `turn.speakers`:

| Field | Meaning |
|---|---|
| `id` | The session's label (`"speaker-0"`, …); words carry it |
| `name`, `identity_id` | The saved person, once the voice matches |
| `identity_score` | How close the match is (cosine, 0–1) |
| `identity_status` | `"MATCHED"`, `"PROVISIONAL"` (too little speech yet) or `"UNKNOWN"` |
| `speech_seconds` | How much of this voice the session has heard |
| `embedding` | The voice over all of its speech so far |

Save a voice in one of two ways, then give the engine the new list:

```python
# From the session: the voice of someone who just spoke.
speaker = next(s for s in turn.speakers if s.name is None)
profiles.append(speaker.profile(name="Mira"))

# From a clean recording of one person (10 s or more).
identifier = await ts.SpeakerIDPipeline.load("TheStageAI/speaker-id-v2")
profiles.append(await identifier.enroll(audio, id="kirill", name="Kirill"))

ts.SpeakerProfile.save_all("speakers.json", profiles)   # the SDK's JSON format
await engine.update_enrolled_speakers(profiles)          # named from now on
```

A profile can hold several voices of one person (`embeddings`, for example one per
recording or microphone); longer recordings count more, up to 30 s each. A voice is
named at a match of 0.55 or more, clearly ahead of the next saved voice, and keeps its
name while the match stays above 0.35.

## Runnable examples

- [`examples/asr_file.py`](../examples/asr_file.py): one-call transcription with word timestamps
- [`examples/asr_engine_live.py`](../examples/asr_engine_live.py): live captions on V5.5 from the microphone, system audio, both, or a pushed WAV; `--speakers` with a `speakers.json` database, `--enroll NAME=WAV`, `--save NAME`
- [`examples/mic_push.py`](../examples/mic_push.py): a microphone you choose, pushed into the engine
