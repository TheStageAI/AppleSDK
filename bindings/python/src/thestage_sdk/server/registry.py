"""Which model serves a request, loaded once and used one request at a time."""

from __future__ import annotations

import asyncio
import logging
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field

from .. import stop_model
from ..audio import ASREngine, ASRPipeline, TSAgentConfig, TSAudioConfig, TTSPipeline
from ..llm import TSLLM
from ..vlm import TSVLM
from .formats import OpenAIError

log = logging.getLogger("thestage_sdk.server")

# ----------------------------------------------------------------------------------------
# Names
# ----------------------------------------------------------------------------------------
KINDS = ("llm", "vlm", "asr", "tts")

# Model names OpenAI clients send by default, served by the configured model.
ALIASES = {
    "asr": {"whisper-1", "gpt-4o-transcribe", "gpt-4o-mini-transcribe"},
    "tts": {"tts-1", "tts-1-hd", "gpt-4o-mini-tts"},
}

# The chat models TheStage ships for Macs (``--llm all``): the default first, then by
# size.
SHIPPED_LLMS = (
    "TheStageAI/Qwen3-0.6B",
    "TheStageAI/LFM2.5-230M",
    "TheStageAI/LFM2.5-350M",
    "TheStageAI/gemma-3-1b-it",
    "TheStageAI/LFM2.5-1.2B",
    "TheStageAI/gemma-4-E2B-it",
)

# Chat models whose pack ships a drafter: ``<repo>:speculative`` is the same model with
# speculative decoding on (greedy, several tokens per step).
DRAFTER_LLMS = frozenset({
    "TheStageAI/LFM2.5-230M",
    "TheStageAI/LFM2.5-350M",
    "TheStageAI/LFM2.5-1.2B",
    "TheStageAI/gemma-4-E2B-it",
})  # fmt: skip
SPECULATIVE = ":speculative"


def split_speculative(requested: str | None) -> tuple[str | None, bool]:
    """
    A request's ``model`` without the ``:speculative`` suffix, and whether it had it.

    Parameters
    ----------
    requested: str or None

    Returns
    -------
    name: str or None
    speculative: bool
    """
    if requested and requested.endswith(SPECULATIVE):
        return requested[: -len(SPECULATIVE)], True
    return requested, False


# OpenAI's voice names; a request for one gets the configured voice.
OPENAI_VOICES = {
    "alloy", "ash", "ballad", "cedar", "coral", "echo", "fable",
    "marin", "nova", "onyx", "sage", "shimmer", "verse",
}  # fmt: skip


# ----------------------------------------------------------------------------------------
# ServerConfig
# ----------------------------------------------------------------------------------------
@dataclass
class ServerConfig:
    """
    What ``thestage-sdk serve`` runs. ``None`` turns a kind off.

    Attributes
    ----------
    llm: str or None
        Default chat model repo id.
    llm_choices: list of str
        More chat models offered in ``/v1/models``, each loaded on first use. One
        language model is loaded at a time: picking another unloads the last.
    vlm: str or None
        Vision model for chat messages with images.
    asr: str or None
        Recogniser for transcriptions and realtime sessions.
    tts: str or None
        Speech model.
    voice: str or None
        Default voice; OpenAI voice names map to it.
    tts_language: str or None
        Text language for multilingual speech models.
    vad: str or None
        VAD that cuts uploaded files in silence; ``None`` cuts at fixed lengths.
    streaming_algorithm: str or None
        Realtime commit policy (``ASRStreamingConfig.algorithm``); ``None`` keeps
        the recogniser pack's. Default ``"THESTAGE_V5_5"``.
    turn_detector: str or None
        Realtime turn detector repo; V5.5 needs it. ``None`` ends turns on silence.
    audio: TSAudioConfig
        Canceller for realtime sessions that capture the Mac's microphone.
    api_key: str or None
        Required bearer token; ``None`` accepts every request.
    allow_any_model: bool
        Load any ``TheStageAI/…`` repo a request names, not only the defaults.
    allow_local_images: bool
        Accept ``image_url`` parts that name a file on the server (a path or
        ``file://``). Off by default: a client could read any image the server
        user can.
    image_fetch_timeout: float
        Seconds to fetch an http(s) ``image_url``. Default 20.
    image_max_bytes: int
        Largest image an http(s) ``image_url`` may return. Default 20 MB.
    """

    # Public Attributes
    # ------------------------------------------------------------------------------------
    llm: str | None = "TheStageAI/Qwen3-0.6B"
    llm_choices: list[str] = field(default_factory=list)
    vlm: str | None = None
    asr: str | None = "TheStageAI/thewhisper-large-v3-turbo"
    tts: str | None = "TheStageAI/neutts-nano-multilingual"
    voice: str | None = "dave"
    tts_language: str | None = None
    vad: str | None = "TheStageAI/silero-vad"
    streaming_algorithm: str | None = "THESTAGE_V5_5"
    turn_detector: str | None = "TheStageAI/smart-turn-v3"
    audio: TSAudioConfig = field(default_factory=TSAudioConfig)
    api_key: str | None = None
    allow_any_model: bool = True
    allow_local_images: bool = False
    image_fetch_timeout: float = 20.0
    image_max_bytes: int = 20 * 1024**2


# ----------------------------------------------------------------------------------------
# Loaders
# ----------------------------------------------------------------------------------------
Loader = Callable[[str, ServerConfig], Awaitable[object]]


def _loaders() -> dict[str, Loader]:
    """
    The default loader for each kind.

    Returns
    -------
    loaders: dict
        ``kind -> async (name, config) -> model``.
    """
    return {
        "llm": lambda name, c: TSLLM.load(name, model_name=name),
        "vlm": lambda name, c: TSVLM.load(name, model_name=name),
        "asr": lambda name, c: ASRPipeline.load(name, model_name=name, vad=c.vad),
        "tts": lambda name, c: TTSPipeline.load(
            name, voice_id=c.voice, language=c.tts_language
        ),
    }


# ----------------------------------------------------------------------------------------
# ModelRegistry
# ----------------------------------------------------------------------------------------
class ModelRegistry:
    """
    Resolves a request's ``model`` to a loaded model of one kind.

    A TheStageAI repo id names that model (loaded on first use when
    ``allow_any_model``); anything else (``"gpt-4o"``, ``"whisper-1"``) gets the
    configured model of that kind. Each model has one lock: the SDK runs one
    inference per model at a time.

    Parameters
    ----------
    config: ServerConfig
    loaders: dict, optional
        ``kind -> async (name, config) -> model``; tests pass fakes.
    engine_factory: callable, optional
        ``async (TSAgentConfig) -> ASREngine``; default ``ASREngine.create``.
    unloader: callable, optional
        ``async (model) -> None`` that frees a language model; default
        ``stop_model`` by its ``model_name``.
    """

    # Constructor
    # ------------------------------------------------------------------------------------
    def __init__(
        self,
        config: ServerConfig,
        loaders: dict[str, Loader] | None = None,
        engine_factory: Callable[[TSAgentConfig], Awaitable[ASREngine]] | None = None,
        unloader: Callable[[object], Awaitable[None]] | None = None,
    ):
        self.config = config
        self._loaders = loaders or _loaders()
        self._engine_factory = engine_factory or ASREngine.create
        self._unloader = unloader or (lambda model: stop_model(model.model_name))
        self._models: dict[tuple[str, str], asyncio.Task] = {}
        self._locks: dict[int, asyncio.Lock] = {}
        # One language model at a time: a switch (unload the others, start the
        # load) runs under this lock so two requests cannot load two models.
        self._llm_switch = asyncio.Lock()

    # Public Methods
    # ------------------------------------------------------------------------------------
    def resolve(self, kind: str, requested: str | None) -> str:
        """
        The repo id that serves a request.

        Parameters
        ----------
        kind: str
            ``"llm"``, ``"vlm"``, ``"asr"`` or ``"tts"``.
        requested: str or None
            The request's ``model``.

        Returns
        -------
        name: str

        Raises
        ------
        OpenAIError
            No model of that kind is configured, the repo is the server's model
            of another kind, or another repo was named with ``allow_any_model``
            off.
        """
        default = getattr(self.config, kind)
        other = next(
            (k for k in KINDS if k != kind and requested == getattr(self.config, k)), None
        )
        if requested and other:
            raise OpenAIError(
                400,
                f"{requested} is this server's {other} model, not a {kind} model",
                code="model_not_found",
                param="model",
            )
        if requested and "/" in requested and requested != default:
            offered = kind == "llm" and requested in self.config.llm_choices
            if not (self.config.allow_any_model or offered):
                raise OpenAIError(
                    404, f"model {requested} is not served", code="model_not_found"
                )
            return requested
        if default is None:
            raise OpenAIError(
                400,
                f"no {kind} model is configured (start the server with --{kind})",
                code="model_not_found",
                param="model",
            )
        return default

    async def get(self, kind: str, requested: str | None = None):
        """
        The loaded model for a request, loading it once on first use.

        Parameters
        ----------
        kind: str
            ``"llm"``, ``"vlm"``, ``"asr"`` or ``"tts"``.
        requested: str, optional
            The request's ``model``.

        Returns
        -------
        model: TSLLM, TSVLM, ASRPipeline or TTSPipeline
        """
        name = self.resolve(kind, requested)
        key = (kind, name)
        if kind == "llm" and key not in self._models:
            async with self._llm_switch:
                if key not in self._models:
                    await self._unload_llms_except(name)
                    self._models[key] = asyncio.ensure_future(
                        self._loaders[kind](name, self.config)
                    )
        if key not in self._models:
            self._models[key] = asyncio.ensure_future(
                self._loaders[kind](name, self.config)
            )
        try:
            return await asyncio.shield(self._models[key])
        except Exception:
            self._models.pop(key, None)  # a failed load is retried next time
            raise

    async def engine(self, config: TSAgentConfig) -> ASREngine:
        """
        A new live transcription engine (one per realtime session).

        Parameters
        ----------
        config: TSAgentConfig

        Returns
        -------
        engine: ASREngine
        """
        return await self._engine_factory(config)

    def lock(self, model) -> asyncio.Lock:
        """
        The lock that serialises inference on one model.

        Parameters
        ----------
        model: object
            A model ``get`` returned.

        Returns
        -------
        lock: asyncio.Lock
        """
        return self._locks.setdefault(id(model), asyncio.Lock())

    def served(self) -> list[tuple[str, str]]:
        """
        The configured models and those loaded since; a chat model with a drafter
        also as ``<repo>:speculative``.

        Returns
        -------
        models: list of tuple
            ``(repo id, kind)``, sorted.
        """
        names = {(getattr(self.config, k), k) for k in KINDS if getattr(self.config, k)}
        names |= {(name, "llm") for name in self.config.llm_choices}
        names |= {(name, kind) for kind, name in self._models}
        drafted = {n for n, k in names if k == "llm" and n in DRAFTER_LLMS}
        names |= {(n + SPECULATIVE, "llm") for n in drafted}
        return sorted(names)

    async def preload(self) -> None:
        """
        Load every configured model now (of the chat models, the default).
        """
        await asyncio.gather(*(self.get(k) for k in KINDS if getattr(self.config, k)))

    # Private Methods
    # ------------------------------------------------------------------------------------
    async def _unload_llms_except(self, name: str) -> None:
        """
        Unload every loaded language model but ``name``, each after its running
        request. A load still in flight is awaited first and then unloaded, so it
        cannot finish later and stay loaded untracked. Call under ``_llm_switch``.

        Parameters
        ----------
        name: str
            The language model about to load.
        """
        for key in [k for k in self._models if k[0] == "llm" and k[1] != name]:
            task = self._models[key]
            try:
                model = await asyncio.shield(task)
            except asyncio.CancelledError:
                if not task.cancelled():
                    raise
                self._models.pop(key, None)
                continue
            except Exception:  # noqa: BLE001 - a failed load holds nothing
                self._models.pop(key, None)
                continue
            self._models.pop(key, None)
            async with self.lock(model):
                await self._unloader(model)
            self._locks.pop(id(model), None)
            log.info("unloaded %s to load %s", key[1], name)
