"""Speech recognition, text to speech, the streaming ASR engine and the
voice agent.

Audio in is 16 kHz mono float32 (any 1-D array-like); audio out is a
float32 NumPy array at the pipeline's ``sample_rate``.
"""

from __future__ import annotations

import json
from collections.abc import AsyncIterator
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from ._host import host
from ._wire import pcm_body
from .tools import Tool, ToolRelay


# ----------------------------------------------------------------------------------------
# Decoding
# ----------------------------------------------------------------------------------------
async def decode_audio(
    data: bytes, sample_rate: int = 16_000, format: str | None = None
) -> np.ndarray:
    """
    Decode an audio file natively (AVAudioFile) to mono float32.

    Parameters
    ----------
    data: bytes
        A whole file: WAV, M4A/AAC, MP3, FLAC, CAF or AIFF.
    sample_rate: int
        The output rate in Hz. Default is 16000, what recognisers take.
    format: str, optional
        The file's extension (``"m4a"``, ``"mp3"``, …); helps MP3 and AAC streams
        without a container.

    Returns
    -------
    samples: numpy.ndarray
        float32 in [-1, 1] at ``sample_rate``.

    Raises
    ------
    SDKError
        ``INVALID_PARAM`` when the bytes are not a readable audio file.
    """
    frame = await host().call(
        "audio.decode", body=bytes(data), sample_rate=sample_rate, format=format
    )
    return frame.pcm.copy()


# ----------------------------------------------------------------------------------------
# ASR
# ----------------------------------------------------------------------------------------
@dataclass
class ASRWord:
    # Public Attributes
    # ------------------------------------------------------------------------------------
    """
    A recognised word with its clock.

    Attributes
    ----------
    text: str
        The word as written (punctuation attached).
    t0: float
        Start, seconds from the beginning of the audio.
    t1: float
        End, seconds.
    is_final: bool
        False while a live turn may still change it.
    speaker_id: str or None
        The speaker, when speakers are on.
    confidence: float or None
        The recogniser's confidence, when it reports one.
    """

    text: str
    t0: float
    t1: float
    is_final: bool = True
    speaker_id: str | None = None
    confidence: float | None = None


@dataclass
class ASRResult:
    # Public Attributes
    # ------------------------------------------------------------------------------------
    """
    A transcript.

    Attributes
    ----------
    text: str
        The whole text.
    words: list of ASRWord
        Word clocks (empty with ``timestamps="NONE"``).
    language: str or None
        The detected or given language code.
    """

    text: str
    words: list[ASRWord]
    language: str | None = None


@dataclass
class SpeakerEmbeddingVector:
    """
    A voice fingerprint (the SDK's ``SpeakerEmbeddingVector``).

    Attributes
    ----------
    values: list of float
        The unit vector.
    embedding_space_id: str
        The speaker model it belongs to; profiles only compare within one space.
    speech_seconds: float or None
        Seconds of speech behind it; a profile weighs its vectors by it.
    """

    # Public Attributes
    # ------------------------------------------------------------------------------------
    values: list[float]
    embedding_space_id: str
    speech_seconds: float | None = None

    # Public Methods
    # ------------------------------------------------------------------------------------
    def to_dict(self) -> dict:
        """
        The SDK's JSON form.

        Returns
        -------
        data: dict
        """
        data = {
            "values": list(self.values),
            "embedding_space_id": self.embedding_space_id,
        }
        if self.speech_seconds is not None:
            data["speech_seconds"] = self.speech_seconds
        return data

    @classmethod
    def from_dict(cls, data: dict) -> SpeakerEmbeddingVector:
        """
        A vector from the SDK's JSON form.

        Parameters
        ----------
        data: dict

        Returns
        -------
        vector: SpeakerEmbeddingVector
        """
        return cls(
            [float(v) for v in data["values"]],
            data["embedding_space_id"],
            data.get("speech_seconds"),
        )


@dataclass
class SpeakerProfile:
    """
    A saved voice: a person and one or more of their voice vectors (the SDK's
    ``SpeakerProfile``; one vector per recording it was saved from).

    Attributes
    ----------
    id: str
        Your id for the person; turns report it as ``ASRSpeaker.identity_id``.
    name: str
        The name turns report as ``ASRSpeaker.name``.
    embeddings: list of SpeakerEmbeddingVector
        The voice.
    """

    # Public Attributes
    # ------------------------------------------------------------------------------------
    id: str
    name: str
    embeddings: list[SpeakerEmbeddingVector]

    # Public Methods
    # ------------------------------------------------------------------------------------
    def to_dict(self) -> dict:
        """
        The SDK's JSON form (what Swift's ``JSONDecoder`` reads).

        Returns
        -------
        data: dict
        """
        return {
            "id": self.id,
            "name": self.name,
            "embeddings": [e.to_dict() for e in self.embeddings],
        }

    @classmethod
    def from_dict(cls, data: dict) -> SpeakerProfile:
        """
        A profile from the SDK's JSON form.

        Parameters
        ----------
        data: dict

        Returns
        -------
        profile: SpeakerProfile
        """
        return cls(
            data["id"],
            data["name"],
            [SpeakerEmbeddingVector.from_dict(e) for e in data["embeddings"]],
        )

    @staticmethod
    def load_all(path: str | Path) -> list[SpeakerProfile]:
        """
        Read a speakers database: a JSON list of profiles.

        Parameters
        ----------
        path: str or Path
            The file; a missing file is an empty database.

        Returns
        -------
        profiles: list of SpeakerProfile
        """
        path = Path(path)
        if not path.exists():
            return []
        return [SpeakerProfile.from_dict(d) for d in json.loads(path.read_text())]

    @staticmethod
    def save_all(path: str | Path, profiles: list[SpeakerProfile]) -> None:
        """
        Write a speakers database: a JSON list of profiles.

        Parameters
        ----------
        path: str or Path
            The file; replaced as a whole.
        profiles: list of SpeakerProfile
        """
        Path(path).write_text(json.dumps([p.to_dict() for p in profiles], indent=2))


@dataclass
class ASRSpeaker:
    """
    A speaker of the session (the SDK's ``ASRSpeaker``).

    Attributes
    ----------
    id: str
        The session's id for the voice (``"speaker-0"``, …); words carry it.
    name: str or None
        The saved name, once the voice matches a profile.
    identity_id: str or None
        The matching profile's id.
    identity_score: float or None
        The cosine score of that match.
    identity_status: str
        ``"MATCHED"``, ``"PROVISIONAL"`` or ``"UNKNOWN"``.
    speech_seconds: float
        Seconds of this voice so far.
    embedding: SpeakerEmbeddingVector or None
        The voice over all of its speech so far; save it with ``profile``.
    revision: int
        Grows when the row changes.
    """

    # Public Attributes
    # ------------------------------------------------------------------------------------
    id: str
    name: str | None = None
    identity_id: str | None = None
    identity_score: float | None = None
    identity_status: str = "UNKNOWN"
    speech_seconds: float = 0.0
    embedding: SpeakerEmbeddingVector | None = None
    revision: int = 0

    # Public Methods
    # ------------------------------------------------------------------------------------
    def profile(self, name: str, id: str | None = None) -> SpeakerProfile:
        """
        Save this voice as a person.

        Parameters
        ----------
        name: str
            The name turns will report.
        id: str, optional
            The profile id. Default is the name.

        Returns
        -------
        profile: SpeakerProfile

        Raises
        ------
        ValueError
            When the speaker has no voice vector yet (identity off, or too little
            speech).
        """
        if self.embedding is None:
            raise ValueError(f"{self.id} has no voice vector yet")
        return SpeakerProfile(id or name, name, [self.embedding])


@dataclass
class ASRTurn:
    """
    One turn of live speech, cumulative: each update holds the whole turn so far.
    The fields follow the SDK's ``ASRTurn`` (AssemblyAI Universal-Streaming names).

    Attributes
    ----------
    turn_order: int
        The turn's number in the session.
    transcript: str
        The text: words so far, formatted on the last update.
    utterance: str
        The finished sentence(s) of the turn, for a voice agent to act on.
    committed: str
        Final text; it only grows within a turn.
    hypothesis: str
        The live tail after ``committed``; it may change.
    end_of_turn: bool
        True on the turn's last update.
    turn_is_formatted: bool
        True when ``transcript`` is punctuated and cased.
    end_of_turn_confidence: float or None
        The turn detector's confidence that the turn ended.
    words: list of ASRWord
        The turn's words with clocks; ``is_final`` marks committed ones.
    language: str or None
        The turn's language.
    speaker_id: str or None
        Who spoke, when speakers are on.
    speakers: list of ASRSpeaker
        The session's speakers, with names once they match saved voices.
    speaker_revision: int
        Grows when speaker labels or names change.
    """

    # Public Attributes
    # ------------------------------------------------------------------------------------
    turn_order: int
    committed: str
    hypothesis: str
    end_of_turn: bool
    words: list[ASRWord]
    transcript: str = ""
    utterance: str = ""
    turn_is_formatted: bool = False
    end_of_turn_confidence: float | None = None
    language: str | None = None
    speaker_id: str | None = None
    speakers: list[ASRSpeaker] = field(default_factory=list)
    speaker_revision: int = 0


# ----------------------------------------------------------------------------------------
# Private helpers
# ----------------------------------------------------------------------------------------
def _words(items: list[dict]) -> list[ASRWord]:
    """
    Words from the bridge's JSON.

    Parameters
    ----------
    items: list of dict

    Returns
    -------
    words: list of ASRWord
    """
    return [ASRWord(**w) for w in items]


def _speaker(d: dict) -> ASRSpeaker:
    """
    A speaker row from the bridge's JSON.

    Parameters
    ----------
    d: dict

    Returns
    -------
    speaker: ASRSpeaker
    """
    embedding = d.get("embedding")
    return ASRSpeaker(
        id=d["id"],
        name=d.get("name"),
        identity_id=d.get("identity_id"),
        identity_score=d.get("identity_score"),
        identity_status=d.get("identity_status", "UNKNOWN"),
        speech_seconds=d.get("speech_seconds", 0.0),
        embedding=SpeakerEmbeddingVector.from_dict(embedding) if embedding else None,
        revision=d.get("revision", 0),
    )


def _turn(d: dict) -> ASRTurn:
    """
    A turn from the bridge's JSON.

    Parameters
    ----------
    d: dict

    Returns
    -------
    turn: ASRTurn
    """
    return ASRTurn(
        turn_order=d["turn_order"],
        committed=d["committed"],
        hypothesis=d["hypothesis"],
        end_of_turn=d["end_of_turn"],
        words=_words(d.get("words", [])),
        transcript=d.get("transcript", ""),
        utterance=d.get("utterance", ""),
        turn_is_formatted=d.get("turn_is_formatted", False),
        end_of_turn_confidence=d.get("end_of_turn_confidence"),
        language=d.get("language"),
        speaker_id=d.get("speaker_id"),
        speakers=[_speaker(s) for s in d.get("speakers", [])],
        speaker_revision=d.get("speaker_revision", 0),
    )


def _result(r: dict) -> ASRResult:
    """
    A result from the bridge's JSON.

    Parameters
    ----------
    r: dict

    Returns
    -------
    result: ASRResult
    """
    return ASRResult(r["text"], _words(r.get("words", [])), r.get("language"))


# ----------------------------------------------------------------------------------------
# ASRPipeline
# ----------------------------------------------------------------------------------------
class ASRPipeline:
    """
    Transcription of whole recordings (``ASREngine(pipeline:vad:)`` in the SDK):
    with a VAD, long files are cut in silence and silent stretches skipped.

    Attributes
    ----------
    handle: str
        The engine in the native host.
    model_name: str
        The name the recogniser was loaded under.
    sample_rate: int
        The rate the recogniser takes (16000).
    """

    # Constructor
    # ------------------------------------------------------------------------------------
    def __init__(self, handle: str, model_name: str, sample_rate: int):
        self.handle = handle
        self.model_name = model_name
        self.sample_rate = sample_rate

    # Public Methods
    # ------------------------------------------------------------------------------------
    @classmethod
    async def load(
        cls,
        engines_path: str,
        model_name: str | None = None,
        device: str = "npu",
        vad: str | None = "TheStageAI/silero-vad",
    ) -> ASRPipeline:
        """
        Load a recogniser, downloading it on first use.

        Parameters
        ----------
        engines_path: str
            A TheStageAI repo id, e.g. ``"TheStageAI/thewhisper-large-v3-turbo"``,
            ``"TheStageAI/parakeet-tdt-0.6b-v3"``, ``"TheStageAI/Qwen3-ASR-0.6B"``.
        model_name: str, optional
            The name to unload it by. Default is the repo id.
        device: str
            ``"npu"`` (default), ``"gpu"`` or ``"cpu"``.
        vad: str or None
            The VAD repo used to cut long files in silence. ``None`` cuts at fixed
            window lengths. Default is ``"TheStageAI/silero-vad"``.

        Returns
        -------
        asr: ASRPipeline
        """
        frame = await host().call(
            "asr.load",
            engines_path=engines_path,
            model_name=model_name,
            device=device,
            vad=vad,
        )
        r = frame.header["r"]
        host().track(r["model_name"], r["handle"])
        return cls(r["handle"], r["model_name"], r["sample_rate"])

    async def infer(
        self,
        audio,
        language: str = "auto",
        timestamps: str = "WORD",
    ) -> ASRResult:
        """
        Transcribe a whole recording.

        Parameters
        ----------
        audio: array-like
            16 kHz mono float32 samples, 1-D.
        language: str
            ``"auto"`` (default) or a code such as ``"en"``, ``"de"``.
        timestamps: str
            ``"WORD"`` (default) or ``"NONE"``.

        Returns
        -------
        result: ASRResult
        """
        frame = await host().call(
            "asr.infer",
            body=pcm_body(audio),
            asr=self.handle,
            config={"language": language, "timestamps": timestamps},
        )
        return _result(frame.header["r"])

    async def infer_stream(
        self,
        audio,
        language: str = "auto",
        timestamps: str = "WORD",
    ) -> AsyncIterator[tuple[ASRResult, bool]]:
        """
        Transcribe a whole recording, reporting the transcript as it settles.

        Parameters
        ----------
        audio: array-like
            16 kHz mono float32 samples, 1-D.
        language: str
            ``"auto"`` (default) or a code.
        timestamps: str
            ``"WORD"`` (default; partials need word clocks) or ``"NONE"``.

        Yields
        ------
        result: ASRResult
            Before each window, the words no later window can change: the text only
            grows.
        is_final: bool
            True on the last item, which equals ``infer``'s result.
        """
        stream, _ = await host().open_stream(
            "asr.infer_stream",
            body=pcm_body(audio),
            asr=self.handle,
            config={"language": language, "timestamps": timestamps},
        )
        async for frame in stream:
            yield _result(frame.header["d"]), frame.header["e"] == "final"


# ----------------------------------------------------------------------------------------
# SpeakerIDPipeline
# ----------------------------------------------------------------------------------------
class SpeakerIDPipeline:
    """
    Saved voices from clean recordings (the SDK's ``SpeakerIDPipeline``).

    Attributes
    ----------
    handle: str
        The pipeline in the native host.
    sample_rate: int
        The rate it takes (16000).
    embedding_space_id: str
        The space its vectors belong to.
    """

    # Constructor
    # ------------------------------------------------------------------------------------
    def __init__(self, handle: str, sample_rate: int, embedding_space_id: str):
        self.handle = handle
        self.sample_rate = sample_rate
        self.embedding_space_id = embedding_space_id

    # Public Methods
    # ------------------------------------------------------------------------------------
    @classmethod
    async def load(
        cls, engines_path: str = "TheStageAI/speaker-id-v2"
    ) -> SpeakerIDPipeline:
        """
        Load the speaker model, downloading it on first use.

        Parameters
        ----------
        engines_path: str
            The repo id. Default is ``"TheStageAI/speaker-id-v2"``, the engine's.

        Returns
        -------
        identifier: SpeakerIDPipeline
        """
        frame = await host().call("speaker_id.load", engines_path=engines_path)
        r = frame.header["r"]
        return cls(r["handle"], r["sample_rate"], r["embedding_space_id"])

    async def enroll(self, audio, id: str, name: str) -> SpeakerProfile:
        """
        A saved voice from a recording of one person.

        Parameters
        ----------
        audio: array-like
            16 kHz mono float32 samples, 1-D; 10 s or more of clean speech is best.
        id: str
            The profile id.
        name: str
            The name turns will report.

        Returns
        -------
        profile: SpeakerProfile
        """
        frame = await host().call(
            "speaker_id.enroll",
            body=pcm_body(audio),
            speaker_id=self.handle,
            id=id,
            name=name,
        )
        return SpeakerProfile.from_dict(frame.header["r"]["profile"])


# ----------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------
# TTS
# ----------------------------------------------------------------------------------------
@dataclass
class TTSResult:
    # Public Attributes
    # ------------------------------------------------------------------------------------
    """
    A whole synthesised clip.

    Attributes
    ----------
    samples: numpy.ndarray
        float32 mono audio.
    sample_rate: int
        Its rate in Hz (24000 for NeuTTS and Qwen3-TTS).
    duration: float
        Seconds of audio.
    rtf: float
        Speed: audio seconds per compute second (× real time).
    """

    samples: np.ndarray
    sample_rate: int
    duration: float
    rtf: float


# ----------------------------------------------------------------------------------------
# TTSStream
# ----------------------------------------------------------------------------------------
class TTSStream:
    """
    Speech from text that arrives in pieces (``TTSPipeline.open_stream``).
    Iterate it for the audio; send text, then close.

    Attributes
    ----------
    sample_rate: int
        The rate of the audio chunks in Hz.
    """

    # Constructor
    # ------------------------------------------------------------------------------------
    def __init__(self, stream, sample_rate: int):
        self._stream = stream
        self.sample_rate = sample_rate

    # Public Methods
    # ------------------------------------------------------------------------------------
    async def send(self, text: str) -> None:
        """
        Add text to speak.

        Parameters
        ----------
        text: str
        """
        await host().call("tts.send", stream=self._stream.id, text=text)

    async def close(self) -> None:
        """
        No more text: the rest is spoken, then the iterator ends.
        """
        await host().call("tts.close", stream=self._stream.id)

    async def cancel(self) -> None:
        """
        Drop the text and audio not yet delivered; the iterator ends.
        """
        await host().call("tts.cancel", stream=self._stream.id)

    def __aiter__(self):
        return self._chunks()

    # Private Methods
    # ------------------------------------------------------------------------------------
    async def _chunks(self) -> AsyncIterator[np.ndarray]:
        """
        The stream's audio.

        Yields
        ------
        samples: numpy.ndarray
            float32 mono chunks at ``sample_rate``, as speech is made.
        """
        async for frame in self._stream:
            yield frame.pcm


# ----------------------------------------------------------------------------------------
# TTSPipeline
# ----------------------------------------------------------------------------------------
class TTSPipeline:
    """
    A loaded voice (``TheStageAI.start_model(TSTTSPipeline.self, …)``).

    Attributes
    ----------
    handle: str
        The model in the native host.
    sample_rate: int
        The rate of the audio it makes in Hz.
    """

    # Constructor
    # ------------------------------------------------------------------------------------
    def __init__(self, handle: str, sample_rate: int):
        self.handle = handle
        self.sample_rate = sample_rate

    # Public Methods
    # ------------------------------------------------------------------------------------
    @classmethod
    async def load(
        cls,
        engines_path: str,
        voice_id: str | None = None,
        language: str | None = None,
        device: str = "npu",
    ) -> TTSPipeline:
        """
        Load a text-to-speech model, downloading it on first use.

        Parameters
        ----------
        engines_path: str
            A TheStageAI repo id, e.g. ``"TheStageAI/neutts-nano-multilingual"``.
        voice_id: str, optional
            A bundled voice (NeuTTS: ``"paul"``, ``"dave"``, ``"jo"``). Default is
            the model's.
        language: str, optional
            The text's language for multilingual models, e.g. ``"english"``.
        device: str
            ``"npu"`` (default), ``"gpu"`` or ``"cpu"``.

        Returns
        -------
        tts: TTSPipeline
        """
        frame = await host().call(
            "tts.load",
            engines_path=engines_path,
            voice_id=voice_id,
            language=language,
            device=device,
        )
        r = frame.header["r"]
        host().track(r["model_name"], r["handle"])
        return cls(r["handle"], r["sample_rate"])

    async def set_voice(self, voice_id: str, language: str | None = None) -> None:
        """
        Switch the voice without reloading.

        Parameters
        ----------
        voice_id: str
            A bundled voice of the model.
        language: str, optional
            The text's language for multilingual models.

        Raises
        ------
        SDKError
            The model has no such voice.
        """
        await host().call(
            "tts.set_voice", tts=self.handle, voice_id=voice_id, language=language
        )

    async def infer(self, text: str, config: dict | None = None) -> TTSResult:
        """
        Synthesise a whole clip.

        Parameters
        ----------
        text: str
        config: dict, optional
            ``temperature`` (float), ``top_k`` (int), ``seed`` (int),
            ``sample_rate_out`` (int, resample the output). Keys left out keep the
            model's values.

        Returns
        -------
        result: TTSResult
        """
        frame = await host().call(
            "tts.infer", tts=self.handle, text=text, config=config or {}
        )
        r = frame.header["r"]
        return TTSResult(frame.pcm.copy(), r["sample_rate"], r["duration"], r["rtf"])

    async def open_stream(self, config: dict | None = None) -> TTSStream:
        """
        Start speech from text that arrives in pieces.

        Parameters
        ----------
        config: dict, optional
            ``temperature`` (float), ``top_k`` (int), ``seed`` (int),
            ``sample_rate_out`` (int, resample the output). Keys left out keep the
            model's values.

        Returns
        -------
        stream: TTSStream
        """
        stream, r = await host().open_stream(
            "tts.open_stream", tts=self.handle, config=config or {}
        )
        return TTSStream(stream, r["sample_rate"])


# ----------------------------------------------------------------------------------------
# Engine and agent configuration
# ----------------------------------------------------------------------------------------
@dataclass
class TSAudioConfig:
    """
    Where audio comes from and how it is cleaned (the SDK's ``AudioEngineConfig``).

    Attributes
    ----------
    source: str
        ``"microphone"`` (the macOS default input; default), ``"system"``
        (everything the Mac plays; macOS 14.2+ and the Screen & System Audio
        Recording permission), ``"meeting"`` (system output and the microphone)
        or ``"push"`` (samples sent with ``ASREngine.push``).
    aec: str or None
        Echo canceller: ``None`` keeps the platform's (WebRTC on macOS);
        ``"webrtc"``, ``"vpio"``, ``"neural"`` or ``"none"``. System and meeting
        capture take none.
    agc: bool or None
        Automatic gain on the microphone.
    mute_mic_during_playback: bool or None
        Voice agent: drop the microphone while it speaks.
    aec_warmup_ms: int or None
        Silence played at start so the canceller converges.
    sample_rate_out: int or None
        Voice agent playback rate in Hz.
    """

    # Public Attributes
    # ------------------------------------------------------------------------------------
    source: str = "microphone"
    aec: str | None = None
    agc: bool | None = None
    mute_mic_during_playback: bool | None = None
    aec_warmup_ms: int | None = None
    sample_rate_out: int | None = None

    # Public Methods
    # ------------------------------------------------------------------------------------
    def params(self) -> dict:
        """
        The bridge parameters: the fields that are set.

        Returns
        -------
        params: dict
        """
        return {k: v for k, v in vars(self).items() if v is not None}


@dataclass
class ASRStreamingConfig:
    """
    How live text is committed (the SDK's ``ASRStreamingConfig``).

    Attributes
    ----------
    algorithm: str or None
        The commit policy, by its SDK name: ``"THESTAGE_V5_5"`` (V5 with the VAD
        energy hold and SmartTurn; needs ``TSAgentConfig.turn_detector``),
        ``"THESTAGE_V5"``, ``"THESTAGE_V6"`` or ``"NAIVE"``. Default is ``None``, the
        recogniser pack's own.
    """

    # Public Attributes
    # ------------------------------------------------------------------------------------
    algorithm: str | None = None

    # Public Methods
    # ------------------------------------------------------------------------------------
    def params(self) -> dict:
        """
        The bridge parameters: the fields that are set.

        Returns
        -------
        params: dict
        """
        return {k: v for k, v in vars(self).items() if v is not None}


@dataclass
class SpeakerVoiceChangeConfig:
    """
    Split a diarizer label where its voice changes (the SDK's
    ``SpeakerVoiceChangeConfig``). A field left ``None`` keeps the SDK's value.

    Attributes
    ----------
    piece_s: float or None
        Length of each scored piece of a label's speech (SDK: 2.0 s).
    hop_s: float or None
        Step between pieces (SDK: 0.25 s).
    voice_delay_s: float or None
        A piece is scored against the label's voice from pieces older than this
        (SDK: 30 s).
    threshold: float or None
        Pieces below this cosine are another person (SDK: 0.30).
    run_s: float or None
        How much low-scoring speech fires the split (SDK: 2.0 s).
    """

    # Public Attributes
    # ------------------------------------------------------------------------------------
    piece_s: float | None = None
    hop_s: float | None = None
    voice_delay_s: float | None = None
    threshold: float | None = None
    run_s: float | None = None

    # Public Methods
    # ------------------------------------------------------------------------------------
    def params(self) -> dict:
        """
        The bridge parameters: the fields that are set.

        Returns
        -------
        params: dict
        """
        return {k: v for k, v in vars(self).items() if v is not None}


@dataclass
class SpeakerLongTurnMergeConfig:
    """
    Merge two speakers a long turn shows are one person (the SDK's
    ``SpeakerLongTurnMergeConfig``). A field left ``None`` keeps the SDK's value.

    Attributes
    ----------
    min_turn_s: float or None
        A turn at least this long is checked (SDK: 8 s).
    threshold: float or None
        The turn's cosine against another speaker that merges the two (SDK: 0.80).
    """

    # Public Attributes
    # ------------------------------------------------------------------------------------
    min_turn_s: float | None = None
    threshold: float | None = None

    # Public Methods
    # ------------------------------------------------------------------------------------
    def params(self) -> dict:
        """
        The bridge parameters: the fields that are set.

        Returns
        -------
        params: dict
        """
        return {k: v for k, v in vars(self).items() if v is not None}


@dataclass
class SpeakerEvidenceConfig:
    """
    What counts as a speaker's voice evidence and when a turn may open a new speaker
    (the SDK's ``SpeakerEvidenceConfig``). A field left ``None`` keeps the SDK's value.

    Attributes
    ----------
    turn_evidence: bool or None
        A turn pinned to a speaker counts as that speaker's evidence (SDK: True).
    new_speaker_min_turn_s: float or None
        A turn that fits no speaker opens a new one only with at least this much
        speech (SDK: 6 s; 0 lets any turn open one).
    turn_born: bool or None
        Whether a turn may open a new speaker at all (SDK: True). False: the
        diarizer alone decides how many people there are and embeddings only
        match turns and labels to speakers that exist.
    skip_overlap: bool or None
        A label's evidence leaves out the moments another label was speaking
        (SDK: True).
    """

    # Public Attributes
    # ------------------------------------------------------------------------------------
    turn_evidence: bool | None = None
    new_speaker_min_turn_s: float | None = None
    turn_born: bool | None = None
    skip_overlap: bool | None = None

    # Public Methods
    # ------------------------------------------------------------------------------------
    def params(self) -> dict:
        """
        The bridge parameters: the fields that are set.

        Returns
        -------
        params: dict
        """
        return {k: v for k, v in vars(self).items() if v is not None}


@dataclass
class SpeakerIDConfig:
    """
    Who the speakers are (the SDK's ``SpeakerIDConfig``). A field left ``None`` keeps
    the SDK's value; a rule left ``None`` is off.

    Attributes
    ----------
    enrolled: list of SpeakerProfile
        Saved voices to name speakers by; ``ASREngine.update_enrolled_speakers``
        replaces them while the engine runs.
    identity_threshold: float or None
        A speaker takes its best saved voice at or above this cosine (SDK: 0.55).
    identity_neg_threshold: float or None
        A named speaker keeps the name while its score stays above this (SDK: 0.35).
    identity_margin: float or None
        How far the best saved voice must lead the second-best (SDK: 0.10).
    min_identity_speech_s: float or None
        Speech a label needs before it is matched (SDK: 2.0 s).
    update_speech_s: float or None
        Speech between later matches of a label (SDK: 2.0 s).
    rejoin_threshold: float or None
        A new label joins a session speaker nobody else owns at this cosine
        (SDK: 0.45).
    split_rejoin_s: float or None
        A voice-change split label stays provisional under its parent until it has
        this much evidence, then rejoins the parent or leaves (SDK: off).
    label_reseed_s: float or None
        A label whose pieces keep failing the fit gate is re-seeded from them once they
        hold this much speech in a row, then joins or opens a speaker again (SDK: off).
    turn_identity: bool or None
        Each long speaker turn is embedded and can move to the speaker it matches
        (SDK: on); ``False`` keeps the diarizer's labels as the speakers.
    voice_change: SpeakerVoiceChangeConfig or None
        Split a label where its voice changes; ``None`` = off.
    long_turn_merge: SpeakerLongTurnMergeConfig or None
        Merge two speakers a long turn shows are one person; ``None`` = off.
    evidence: SpeakerEvidenceConfig or None
        Turn evidence, the new-speaker turn gate and the overlap skip; ``None`` = off.
    """

    # Public Attributes
    # ------------------------------------------------------------------------------------
    enrolled: list[SpeakerProfile] = field(default_factory=list)
    identity_threshold: float | None = None
    identity_neg_threshold: float | None = None
    identity_margin: float | None = None
    min_identity_speech_s: float | None = None
    update_speech_s: float | None = None
    rejoin_threshold: float | None = None
    split_rejoin_s: float | None = None
    label_reseed_s: float | None = None
    turn_identity: bool | None = None
    voice_change: SpeakerVoiceChangeConfig | None = None
    long_turn_merge: SpeakerLongTurnMergeConfig | None = None
    evidence: SpeakerEvidenceConfig | None = None

    # Public Methods
    # ------------------------------------------------------------------------------------
    def params(self) -> dict:
        """
        The bridge parameters: ``enrolled`` always, the scalar fields that are set, and
        each rule that is on as its own dict (``{}`` = the SDK's defaults for it).

        Returns
        -------
        params: dict
        """
        out: dict = {"enrolled": [p.to_dict() for p in self.enrolled]}
        for key in (
            "identity_threshold",
            "identity_neg_threshold",
            "identity_margin",
            "min_identity_speech_s",
            "update_speech_s",
            "rejoin_threshold",
            "split_rejoin_s",
            "label_reseed_s",
            "turn_identity",
        ):
            value = getattr(self, key)
            if value is not None:
                out[key] = value
        for key in ("voice_change", "long_turn_merge", "evidence"):
            rule = getattr(self, key)
            if rule is not None:
                out[key] = rule.params()
        return out


@dataclass
class ASRSpeakerConfig:
    """
    Speakers on the live stream (the SDK's ``ASRSpeakerConfig``): words labelled by
    voice, and named by saved voices.

    Attributes
    ----------
    diarization: str
        The diarizer's repo id.
    identification: str or None
        The speaker-ID repo id; ``None`` labels voices without telling who they are.
    identity: SpeakerIDConfig
        The saved voices.
    """

    # Public Attributes
    # ------------------------------------------------------------------------------------
    diarization: str = "TheStageAI/Nemotron-3-Diarization"
    identification: str | None = "TheStageAI/speaker-id-v2"
    identity: SpeakerIDConfig = field(default_factory=SpeakerIDConfig)

    # Public Methods
    # ------------------------------------------------------------------------------------
    def params(self) -> dict:
        """
        The bridge parameters (``identification: None`` is sent: it turns identity
        off).

        Returns
        -------
        params: dict
        """
        return {
            "diarization": self.diarization,
            "identification": self.identification,
            "identity": self.identity.params(),
        }


@dataclass
class TSAgentConfig:
    """
    The engine and voice agent configuration (the SDK's
    ``TSAgentConfig(vad:stt:turn_detector:)``). A field left ``None`` keeps the SDK's
    default.

    Attributes
    ----------
    stt: str
        The recogniser's repo id.
    vad: str
        The voice activity detector's repo id.
    turn_detector: str or None
        The turn detector's repo id (``"TheStageAI/smart-turn-v3"``); V5.5 and
        ``turn_end_mode="dnn"`` need it.
    language: str
        ``"auto"`` or a language code.
    timestamps: str
        ``"WORD"`` or ``"NONE"``.
    turn_end_mode: str or None
        ``"vad"`` (a silence ends the turn; the SDK default), ``"dnn"`` (the turn
        detector decides at a pause) or ``"none"`` (one continuous turn). V5.5 picks
        ``"dnn"`` itself.
    turn_eot_threshold: float or None
        The turn detector's end-of-turn threshold (V5.5: 0.95).
    turn_pause_trigger_ms: int or None
        Pause in ms before the turn detector is asked (256).
    asr_streaming_config: ASRStreamingConfig
        The commit policy.
    speakers: ASRSpeakerConfig or None
        Speakers on the stream; ``None`` is off.
    audio: TSAudioConfig
        The audio source and canceller.
    """

    # Public Attributes
    # ------------------------------------------------------------------------------------
    stt: str = "TheStageAI/thewhisper-large-v3-turbo"
    vad: str = "TheStageAI/silero-vad"
    turn_detector: str | None = None
    language: str = "auto"
    timestamps: str = "WORD"
    turn_end_mode: str | None = None
    turn_eot_threshold: float | None = None
    turn_pause_trigger_ms: int | None = None
    asr_streaming_config: ASRStreamingConfig = field(default_factory=ASRStreamingConfig)
    speakers: ASRSpeakerConfig | None = None
    audio: TSAudioConfig = field(default_factory=TSAudioConfig)

    # Public Methods
    # ------------------------------------------------------------------------------------
    def params(self) -> dict:
        """
        The bridge parameters.

        Returns
        -------
        params: dict
        """
        params = {
            "stt": self.stt,
            "vad": self.vad,
            "language": self.language,
            "timestamps": self.timestamps,
            "turn_detector": self.turn_detector,
            "turn_end_mode": self.turn_end_mode,
            "turn_eot_threshold": self.turn_eot_threshold,
            "turn_pause_trigger_ms": self.turn_pause_trigger_ms,
            "asr_streaming_config": self.asr_streaming_config.params(),
            "speakers": self.speakers.params() if self.speakers else None,
            "audio": self.audio.params(),
        }
        return {k: v for k, v in params.items() if v is not None}


# ----------------------------------------------------------------------------------------
# ASREngine
# ----------------------------------------------------------------------------------------
class ASREngine:
    """
    Live transcription: voice activity, streaming recognition, turn ends and
    (optionally) speakers.

    Attributes
    ----------
    handle: str
        The engine in the native host.
    """

    # Constructor
    # ------------------------------------------------------------------------------------
    def __init__(self, handle: str):
        self.handle = handle

    # Public Methods
    # ------------------------------------------------------------------------------------
    @classmethod
    async def create(cls, config: TSAgentConfig) -> ASREngine:
        """
        Create an engine; nothing captures until ``start``.

        Parameters
        ----------
        config: TSAgentConfig
            Models, language, turn detection, speakers and ``audio.source``.

        Returns
        -------
        engine: ASREngine
        """
        frame = await host().call("asr_engine.create", **config.params())
        return cls(frame.header["r"]["handle"])

    async def turns(self) -> AsyncIterator[ASRTurn]:
        """
        Subscribe to the engine's turns. Subscribe before ``start``: turns are not
        replayed.

        Returns
        -------
        turns: async iterator of ASRTurn
            Each update of the open turn; ends after ``stop``.
        """
        stream, _ = await host().open_stream("asr_engine.turns", engine=self.handle)

        async def gen():
            async for frame in stream:
                yield _turn(frame.header["d"])

        return gen()

    async def start(self) -> None:
        """
        Start capturing (or accepting ``push``).

        Raises
        ------
        SDKError
            ``AUDIO_CAPTURE_PERMISSION_DENIED`` or ``AUDIO_CAPTURE_UNSUPPORTED`` for
            system and meeting capture.
        """
        await host().call("asr_engine.start", engine=self.handle)

    async def push(self, audio, sample_rate: int = 16_000) -> None:
        """
        Send audio to an engine created with ``TSAudioConfig(source="push")``.

        Parameters
        ----------
        audio: array-like
            Mono float32 samples, about 100 ms at a time, at real-time pace.
        sample_rate: int
            Their rate in Hz (any; the engine resamples). Default is 16000.
        """
        await host().call(
            "asr_engine.push",
            body=pcm_body(audio),
            engine=self.handle,
            sample_rate=sample_rate,
        )

    async def stop(self) -> None:
        """
        Stop the engine; the open turn ends and ``turns`` finishes.
        """
        await host().call("asr_engine.stop", engine=self.handle)

    async def close(self) -> None:
        """
        Free the engine in the native host (``stop`` it first). Until then its
        models and audio graph stay with the handle; later calls fail.
        """
        handle, self.handle = self.handle, ""
        if handle:
            await host().call("sdk.release", handle=handle)

    async def update_enrolled_speakers(self, profiles: list[SpeakerProfile]) -> None:
        """
        Name speakers by these saved voices from now on (a speaker already on the
        call is named as soon as it matches).

        Parameters
        ----------
        profiles: list of SpeakerProfile
            The whole database; it replaces the one the engine had.
        """
        await host().call(
            "asr_engine.update_enrolled_speakers",
            engine=self.handle,
            profiles=[p.to_dict() for p in profiles],
        )


# ----------------------------------------------------------------------------------------
# Voice agent
# ----------------------------------------------------------------------------------------
@dataclass
class TSAgentEvent:
    """
    One voice agent event.

    Attributes
    ----------
    kind: str
        ``state_changed``, ``user_request_partial``, ``user_request``,
        ``response_delta``, ``response_done``, ``playback_started``,
        ``playback_ended``, ``tool_started``, ``tool_ended``, ``wake_word``,
        ``error`` or ``metrics``.
    data: dict
        The event's fields: ``state``; ``text`` and ``source``; ``delta``;
        ``reason``; ``name``; ``prob``.
    """

    # Public Attributes
    # ------------------------------------------------------------------------------------
    kind: str
    data: dict


# ----------------------------------------------------------------------------------------
# TSVoiceAgent
# ----------------------------------------------------------------------------------------
class TSVoiceAgent:
    """
    Speech in, speech out, on the Mac: recognition, a language model you loaded,
    and synthesis.

    Attributes
    ----------
    handle: str
        The agent in the native host.
    """

    # Constructor
    # ------------------------------------------------------------------------------------
    def __init__(self, handle: str, relay: ToolRelay | None = None):
        self.handle = handle
        self._relay = relay

    # Public Methods
    # ------------------------------------------------------------------------------------
    @classmethod
    async def create(
        cls,
        config: TSAgentConfig,
        llm,
        tts: str,
        tts_voice: str | None = None,
        system_prompt: str | None = None,
        tools: list[Tool] | None = None,
    ) -> TSVoiceAgent:
        """
        Create a voice agent; nothing listens until ``start``.

        Parameters
        ----------
        config: TSAgentConfig
            Recognition, turn detection and ``audio`` (canceller, playback rate).
        llm: TSLLM
            A loaded language model; the agent uses it by ``model_name``.
        tts: str
            The text-to-speech repo id.
        tts_voice: str, optional
            A bundled voice. Default is the model's.
        system_prompt: str, optional
            Instructions for the model.
        tools: list of Tool, optional
            Tools the model may call. The agent says a short filler while the tool
            runs, then speaks the answer; ``tool_started`` / ``tool_ended`` events
            mark the call.

        Returns
        -------
        agent: TSVoiceAgent
        """
        tools = list(tools or [])
        frame = await host().call(
            "voice_agent.create",
            llm_model=llm.model_name,
            tts=tts,
            tts_voice=tts_voice,
            system_prompt=system_prompt,
            tools=[tool.definition() for tool in tools] or None,
            **config.params(),
        )
        result = frame.header["r"]
        relay = ToolRelay(host(), result["tools"], tools) if "tools" in result else None
        return cls(result["handle"], relay)

    async def events(self) -> AsyncIterator[TSAgentEvent]:
        """
        Subscribe to the agent's events. Subscribe before ``start``.

        Returns
        -------
        events: async iterator of TSAgentEvent
        """
        stream, _ = await host().open_stream("voice_agent.events", agent=self.handle)

        async def gen():
            async for frame in stream:
                yield TSAgentEvent(frame.header["e"], frame.header.get("d", {}))

        return gen()

    async def start(self) -> None:
        """
        Start listening and speaking.
        """
        await host().call("voice_agent.start", agent=self.handle)

    async def begin_listening(self) -> None:
        """
        Resume listening after ``pause_listening``.
        """
        await host().call("voice_agent.begin_listening", agent=self.handle)

    async def pause_listening(self) -> None:
        """
        Stop listening; the agent still finishes what it is saying.
        """
        await host().call("voice_agent.pause_listening", agent=self.handle)

    async def say(self, text: str) -> None:
        """
        Speak text without asking the model.

        Parameters
        ----------
        text: str
        """
        await host().call("voice_agent.say", agent=self.handle, text=text)

    async def send_request(self, text: str) -> None:
        """
        Send a typed request, as if the user had said it.

        Parameters
        ----------
        text: str
        """
        await host().call("voice_agent.send_request", agent=self.handle, text=text)

    async def interrupt(self) -> None:
        """
        Stop the current reply and its speech.
        """
        await host().call("voice_agent.interrupt", agent=self.handle)

    async def clear_history(self) -> None:
        """
        Forget the conversation.
        """
        await host().call("voice_agent.clear_history", agent=self.handle)

    async def set_system_prompt(self, prompt: str) -> None:
        """
        Replace the model's instructions for the next turns.

        Parameters
        ----------
        prompt: str
        """
        await host().call(
            "voice_agent.set_system_prompt", agent=self.handle, prompt=prompt
        )

    async def stop(self) -> None:
        """
        Stop listening and speaking; ``events`` finishes.
        """
        await host().call("voice_agent.stop", agent=self.handle)

    async def close(self) -> None:
        """
        Free the agent in the native host (``stop`` it first). Until then its
        models, audio graph and tool relay stay with the handle; later calls fail.
        """
        handle, self.handle = self.handle, ""
        self._relay = None
        if handle:
            await host().call("sdk.release", handle=handle)
