"""TheStage on-device AI SDK for Python (Apple Silicon Macs).

The models run natively in ``thestage-host``, a signed helper the wheel
ships; this package sends calls and reads streams, so speed is the native
speed. Everything is ``async``::

    import asyncio
    import thestage_sdk as ts

    async def main():
        await ts.initialize(api_token="…")
        llm = await ts.TSLLM.load("TheStageAI/Qwen3-0.6B")
        # also: ts.TSVLM, ts.ASRPipeline, ts.ASREngine, ts.TTSPipeline,
        # ts.TSVoiceAgent
        async for chunk in llm.infer_stream("Hello"):
            print(chunk.text, end="")

    asyncio.run(main())
"""

from dataclasses import dataclass, field

from ._host import SDKError
from ._host import host as _host
from .audio import (
    ASREngine,
    ASRPipeline,
    ASRResult,
    ASRSpeaker,
    ASRSpeakerConfig,
    ASRStreamingConfig,
    ASRTurn,
    ASRWord,
    SpeakerEmbeddingVector,
    SpeakerEvidenceConfig,
    SpeakerIDConfig,
    SpeakerLongTurnMergeConfig,
    SpeakerVoiceChangeConfig,
    SpeakerIDPipeline,
    SpeakerProfile,
    TSAgentConfig,
    TSAgentEvent,
    TSAudioConfig,
    TSVoiceAgent,
    TTSPipeline,
    TTSResult,
    TTSStream,
    decode_audio,
)
from .llm import (
    TSLLM,
    LLMResult,
    LLMStreamChunk,
    LLMStreamEvent,
    TSChatSession,
)
from .tools import Tool
from .vlm import TSVLM

__version__ = "1.6.0"


async def initialize(api_token: str, hf_token: str | None = None) -> None:
    """
    Start the SDK for this process; call once, before loading a model.

    Parameters
    ----------
    api_token: str
        Your TheStage API token.
    hf_token: str, optional
        A Hugging Face token, for gated repos.
    """
    await _host().call("sdk.initialize", api_token=api_token, hf_token=hf_token)


async def stop_model(model_name: str) -> None:
    """
    Unload a model.

    Parameters
    ----------
    model_name: str
        The name it was loaded under (the repo id unless ``model_name`` was given).
    """
    await _host().call("sdk.stop_model", model_name=model_name)
    await _host().release_model(model_name)


@dataclass
class ModelDeletion:
    """
    What ``delete_model`` removed.

    Attributes
    ----------
    freed_bytes: int
        Bytes freed on disk; 0 when nothing of the pack was on this Mac.
    revisions: list of str
        Revisions whose copies were removed, sorted.
    """

    freed_bytes: int = 0
    revisions: list[str] = field(default_factory=list)


async def delete_model(engines_path: str, revision: str | None = None) -> ModelDeletion:
    """
    Delete a downloaded model from this Mac.

    Removes every on-device copy of the repo (downloads, unpacked engines,
    compiled variants), or only ``revision``'s copies when given. Repeating it is
    safe; a local engines folder is never touched.

    Parameters
    ----------
    engines_path: str
        The Hugging Face repo id the model was loaded from.
    revision: str, optional
        One revision to delete; every revision when omitted.

    Raises
    ------
    SDKError
        ``code == "ModelInUse"`` while the model is loaded (``stop_model`` it
        first); ``code == "ModelBusy"`` while a download or load of it runs.
    """
    frame = await _host().call(
        "sdk.delete_model", engines_path=engines_path, revision=revision
    )
    result = frame.header.get("r") or {}
    return ModelDeletion(
        freed_bytes=int(result.get("freed_bytes", 0)),
        revisions=[str(r) for r in result.get("revisions", [])],
    )


__all__ = [
    "TSLLM",
    "TSVLM",
    "ASREngine",
    "ASRPipeline",
    "ASRResult",
    "ASRSpeaker",
    "ASRSpeakerConfig",
    "ASRStreamingConfig",
    "ASRTurn",
    "ASRWord",
    "LLMResult",
    "LLMStreamChunk",
    "LLMStreamEvent",
    "ModelDeletion",
    "SDKError",
    "SpeakerEmbeddingVector",
    "SpeakerEvidenceConfig",
    "SpeakerIDConfig",
    "SpeakerLongTurnMergeConfig",
    "SpeakerVoiceChangeConfig",
    "SpeakerIDPipeline",
    "SpeakerProfile",
    "TSAgentConfig",
    "TSAgentEvent",
    "TSAudioConfig",
    "TSChatSession",
    "TSVoiceAgent",
    "TTSPipeline",
    "TTSResult",
    "TTSStream",
    "Tool",
    "decode_audio",
    "initialize",
    "stop_model",
    "delete_model",
]
