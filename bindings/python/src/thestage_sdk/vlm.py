"""Vision-language models.

Mirrors the Swift API::

    vlm = await TSVLM.load("TheStageAI/LFM2.5-VL-450M")
    result = await vlm.infer(["photo.jpg"], "Describe this image in one sentence.")
    async for chunk in vlm.infer_stream([jpeg_bytes], "What is on the receipt?"):
        print(chunk.text, end="")

An image is a file path, encoded bytes (JPEG, PNG, HEIC), or a PIL image.
"""

from __future__ import annotations

import io
import os
from collections.abc import AsyncIterator

from ._host import host
from .llm import LLMResult, LLMStreamChunk


# ----------------------------------------------------------------------------------------
# Images
# ----------------------------------------------------------------------------------------
def _images(images) -> tuple[list[str], list[int], bytes]:
    """
    Split images into paths and encoded bytes for one call.

    Parameters
    ----------
    images: list
        File paths, encoded bytes (JPEG, PNG, HEIC) or PIL images.

    Returns
    -------
    paths: list of str
        Images the native host reads from disk.
    lengths: list of int
        Byte counts of the images in ``body``, in order.
    body: bytes
        The encoded images back to back.
    """
    paths, lengths, body = [], [], bytearray()
    for image in images:
        if isinstance(image, (str, os.PathLike)):
            paths.append(os.fspath(image))
            continue
        if hasattr(image, "save"):
            buffer = io.BytesIO()
            image.save(buffer, format="PNG")
            image = buffer.getvalue()
        data = bytes(image)
        lengths.append(len(data))
        body += data
    return paths, lengths, bytes(body)


# ----------------------------------------------------------------------------------------
# TSVLM
# ----------------------------------------------------------------------------------------
class TSVLM:
    """
    A loaded vision-language model (``TheStageAI.start_model(TSVLM.self, …)``).

    Attributes
    ----------
    handle: str
        The model in the native host.
    model_name: str
        The name it was loaded under.
    generation_defaults: dict
        The model's own decoding settings; ``config`` arguments override them.
    """

    # Constructor
    # ------------------------------------------------------------------------------------
    def __init__(self, handle: str, model_name: str, generation_defaults: dict):
        self.handle = handle
        self.model_name = model_name
        self.generation_defaults = generation_defaults

    # Public Methods
    # ------------------------------------------------------------------------------------
    @classmethod
    async def load(
        cls,
        engines_path: str,
        model_name: str | None = None,
        device: str = "npu",
    ) -> TSVLM:
        """
        Load a vision-language model, downloading it on first use.

        Parameters
        ----------
        engines_path: str
            A TheStageAI repo id, e.g. ``"TheStageAI/LFM2.5-VL-450M"``.
        model_name: str, optional
            The name to unload it by. Default is the repo id.
        device: str
            ``"npu"`` (default), ``"gpu"`` or ``"cpu"``.

        Returns
        -------
        vlm: TSVLM
        """
        frame = await host().call(
            "vlm.load",
            engines_path=engines_path,
            model_name=model_name,
            device=device,
        )
        r = frame.header["r"]
        host().track(r["model_name"], r["handle"])
        return cls(r["handle"], r["model_name"], r["generation_defaults"])

    async def infer(
        self,
        images,
        prompt: str,
        system_prompt: str | None = None,
        config: dict | None = None,
    ) -> LLMResult:
        """
        Answer a prompt about images, as one reply.

        Parameters
        ----------
        images: list
            File paths, encoded bytes (JPEG, PNG, HEIC) or PIL images.
        prompt: str
            The question or instruction.
        system_prompt: str, optional
            Instructions for the model. Default is the model's own.
        config: dict, optional
            Overrides of the model's ``generation_defaults``, key by key:
            ``max_new_tokens``, ``min_new_tokens``, ``temperature``, ``top_k``,
            ``top_p``, ``min_p``, ``repetition_penalty``, ``seed``,
            ``enable_thinking``, ``stop_sequences``, ``speculative_decoding``.
            Keys left out keep the model's value.

        Returns
        -------
        result: LLMResult
        """
        paths, lengths, body = _images(images)
        frame = await host().call(
            "vlm.infer",
            body=body,
            vlm=self.handle,
            prompt=prompt,
            system_prompt=system_prompt,
            config=config or {},
            image_paths=paths,
            image_lengths=lengths,
        )
        return LLMResult(**frame.header["r"])

    async def infer_stream(
        self,
        images,
        prompt: str | None = None,
        system_prompt: str | None = None,
        config: dict | None = None,
        *,
        messages: list[dict] | None = None,
    ) -> AsyncIterator[LLMStreamChunk]:
        """
        Answer a prompt or a conversation about images, token by token.

        Parameters
        ----------
        images: list
            File paths, encoded bytes (JPEG, PNG, HEIC) or PIL images.
        prompt: str, optional
            The question or instruction. Give this or ``messages``.
        system_prompt: str, optional
            Instructions for the model. Default is the model's own.
        config: dict, optional
            Overrides of the model's ``generation_defaults``, key by key:
            ``max_new_tokens``, ``min_new_tokens``, ``temperature``, ``top_k``,
            ``top_p``, ``min_p``, ``repetition_penalty``, ``seed``,
            ``enable_thinking``, ``stop_sequences``, ``speculative_decoding``.
            Keys left out keep the model's value.
        messages: list of dict, optional
            A conversation instead of ``prompt``: ``{"role", "content"}``.

        Yields
        ------
        chunk: LLMStreamChunk
        """
        paths, lengths, body = _images(images)
        stream, _ = await host().open_stream(
            "vlm.infer_stream",
            body=body,
            vlm=self.handle,
            prompt=prompt,
            messages=messages,
            system_prompt=system_prompt,
            config=config or {},
            image_paths=paths,
            image_lengths=lengths,
        )
        async for frame in stream:
            d = frame.header["d"]
            yield LLMStreamChunk(
                text=d.get("text", ""),
                token_index=d.get("token_index", 0),
                is_final=d.get("is_final", False),
                tokens_per_second=d.get("tokens_per_second"),
                generated_tokens=d.get("generated_tokens"),
                prompt_tokens=d.get("prompt_tokens"),
                time_to_first_token=d.get("time_to_first_token"),
                stop_reason=d.get("stop_reason"),
            )
