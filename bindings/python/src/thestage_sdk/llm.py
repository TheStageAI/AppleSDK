"""Language models and chat sessions.

Mirrors the Swift API::

    llm = await TSLLM.load("TheStageAI/Qwen3-0.6B")
    async for chunk in llm.infer_stream("Tell me a short story."):
        print(chunk.text, end="")

    session = TSChatSession(llm, system_prompt="Be brief.")
    async for event in session.infer_stream("My name is Ada."):
        if event.kind == "text_delta":
            print(event.text, end="")
"""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator
from dataclasses import dataclass, field
from typing import TYPE_CHECKING

from ._host import host
from .tools import Tool, ToolRelay

if TYPE_CHECKING:
    from typing_extensions import Self


# ----------------------------------------------------------------------------------------
# Results and events
# ----------------------------------------------------------------------------------------
@dataclass
class LLMStreamChunk:
    """
    One decoded piece of a ``TSLLM.infer_stream`` reply.

    Attributes
    ----------
    text: str
        The new text (empty on the final chunk).
    token_index: int
        Index of the token in the reply.
    is_final: bool
        True on the last chunk, which carries the metrics below.
    tokens_per_second: float or None
        Decode speed the SDK measured.
    generated_tokens: int or None
        Tokens in the reply.
    prompt_tokens: int or None
        Tokens in the prompt.
    time_to_first_token: float or None
        Seconds from the call to the first token.
    stop_reason: str or None
        ``eos``, ``max_new_tokens`` or ``stop_sequence``.
    """

    # Public Attributes
    # ------------------------------------------------------------------------------------
    text: str
    token_index: int
    is_final: bool
    tokens_per_second: float | None = None
    generated_tokens: int | None = None
    prompt_tokens: int | None = None
    time_to_first_token: float | None = None
    stop_reason: str | None = None


@dataclass
class LLMResult:
    # Public Attributes
    # ------------------------------------------------------------------------------------
    """
    A whole reply from ``TSLLM.infer`` or ``TSVLM.infer``.

    Attributes
    ----------
    text: str
        The reply.
    prompt_tokens: int
        Tokens in the prompt.
    generated_tokens: int
        Tokens in the reply.
    prefill_seconds: float
        Time to read the prompt.
    decode_seconds: float
        Time to generate the reply.
    """

    text: str
    prompt_tokens: int
    generated_tokens: int
    prefill_seconds: float
    decode_seconds: float


@dataclass
class LLMStreamEvent:
    """
    One event of a chat stream (``TSChatSession.infer_stream``,
    ``TSLLM.infer_events``).

    Attributes
    ----------
    kind: str
        ``text_delta``, ``thinking_delta``, ``tool_call``, ``tool_result``,
        ``tool_round`` or ``final``.
    data: dict
        The event's fields: ``text`` for the deltas; ``name`` and ``arguments``
        for ``tool_call``; ``name`` and ``content`` for ``tool_result``;
        ``stop_reason``, ``prompt_tokens``, ``generated_tokens``,
        ``tokens_per_second``, ``total_seconds`` and ``raw_text`` for ``final``.
    """

    # Public Attributes
    # ------------------------------------------------------------------------------------
    kind: str
    data: dict = field(default_factory=dict)

    # Public Methods
    # ------------------------------------------------------------------------------------
    @property
    def text(self) -> str:
        """
        The event's text (empty when it has none).

        Returns
        -------
        text: str
        """
        return self.data.get("text", "")


# ----------------------------------------------------------------------------------------
# TSLLM
# ----------------------------------------------------------------------------------------
class TSLLM:
    """
    A loaded language model (``TheStageAI.start_model(TSLLM.self, …)``).

    Attributes
    ----------
    handle: str
        The model in the native host.
    model_name: str
        The name it was loaded under (``stop_model`` unloads it by this name).
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
    ) -> TSLLM:
        """
        Load a language model, downloading it on first use.

        Parameters
        ----------
        engines_path: str
            A TheStageAI repo id, e.g. ``"TheStageAI/Qwen3-0.6B"``.
        model_name: str, optional
            The name to unload it by. Default is the repo id.
        device: str
            ``"npu"`` (Neural Engine, default), ``"gpu"`` or ``"cpu"``.

        Returns
        -------
        llm: TSLLM
        """
        frame = await host().call(
            "llm.load",
            engines_path=engines_path,
            model_name=model_name,
            device=device,
        )
        r = frame.header["r"]
        host().track(r["model_name"], r["handle"])
        return cls(r["handle"], r["model_name"], r["generation_defaults"])

    async def infer(
        self,
        prompt: str,
        system_prompt: str | None = None,
        config: dict | None = None,
    ) -> LLMResult:
        """
        Generate a whole reply to one prompt.

        Parameters
        ----------
        prompt: str
            The user's message.
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
        frame = await host().call(
            "llm.infer",
            llm=self.handle,
            prompt=prompt,
            system_prompt=system_prompt,
            config=config or {},
        )
        return LLMResult(**frame.header["r"])

    async def infer_stream(
        self,
        prompt: str | None = None,
        system_prompt: str | None = None,
        config: dict | None = None,
        *,
        messages: list[dict] | None = None,
    ) -> AsyncIterator[LLMStreamChunk]:
        """
        Generate a reply token by token.

        Parameters
        ----------
        prompt: str, optional
            The user's message. Give this or ``messages``.
        system_prompt: str, optional
            Instructions for the model. Default is the model's own.
        config: dict, optional
            Overrides of the model's ``generation_defaults``, key by key:
            ``max_new_tokens``, ``min_new_tokens``, ``temperature``, ``top_k``,
            ``top_p``, ``min_p``, ``repetition_penalty``, ``seed``,
            ``enable_thinking``, ``stop_sequences``, ``speculative_decoding``.
            Keys left out keep the model's value.
        messages: list of dict, optional
            A whole conversation instead of ``prompt``: ``{"role": "user" |
            "assistant" | "system" | "tool", "content": str}``. Trimmed to the
            model's context, oldest turns first.

        Yields
        ------
        chunk: LLMStreamChunk
            Text as it decodes; the last chunk (``is_final``) carries the metrics.
        """
        stream, _ = await host().open_stream(
            "llm.infer_stream",
            llm=self.handle,
            prompt=prompt,
            messages=messages,
            system_prompt=system_prompt,
            config=config or {},
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

    async def infer_events(
        self,
        messages: list[dict],
        tools: list[dict] | None = None,
        system_prompt: str | None = None,
        config: dict | None = None,
    ) -> AsyncIterator[LLMStreamEvent]:
        """
        Generate a reply to a conversation, with tools the caller runs.

        When the model calls a tool, a ``tool_call`` event arrives and the stream ends
        with ``final``. Run the tool, then call again with the assistant's
        ``raw_text`` (from ``final``) and a ``tool`` message holding the result.

        Parameters
        ----------
        messages: list of dict
            ``{"role": "system" | "user" | "assistant" | "tool", "content": str,
            "name": str}``; a ``tool`` message carries a result and ``name`` the
            tool. Trimmed to the model's context, oldest turns first.
        tools: list of dict, optional
            ``{"name": str, "description": str, "parameters": <JSON Schema>}``.
            Needs a pack with a tool format (Qwen3, LFM2, Gemma 3/4).
        system_prompt: str, optional
            Instructions for the model. Default is the model's own.
        config: dict, optional
            Overrides of the model's ``generation_defaults``, key by key:
            ``max_new_tokens``, ``min_new_tokens``, ``temperature``, ``top_k``,
            ``top_p``, ``min_p``, ``repetition_penalty``, ``seed``,
            ``enable_thinking``, ``stop_sequences``, ``speculative_decoding``.
            Keys left out keep the model's value.

        Yields
        ------
        event: LLMStreamEvent
            ``text_delta``, ``thinking_delta``, ``tool_call``, then ``final``.
        """
        stream, _ = await host().open_stream(
            "llm.infer_events",
            llm=self.handle,
            messages=messages,
            tools=tools,
            system_prompt=system_prompt,
            config=config or {},
        )
        async for frame in stream:
            yield LLMStreamEvent(frame.header["e"], frame.header.get("d", {}))

    def chat_session(
        self,
        system_prompt: str | None = None,
        max_turns: int | None = None,
        tools: list[Tool] | None = None,
    ) -> TSChatSession:
        """
        A multi-turn chat on this model; the same as ``TSChatSession(llm, …)``.

        Parameters
        ----------
        system_prompt: str, optional
            Instructions for the model. Default is the model's own.
        max_turns: int, optional
            Turns kept in memory (sliding window). Default is the SDK's.
        tools: list of Tool, optional
            Tools the model may call; the session runs them and continues.

        Returns
        -------
        session: TSChatSession
        """
        return TSChatSession(
            self, system_prompt=system_prompt, max_turns=max_turns, tools=tools
        )


# ----------------------------------------------------------------------------------------
# TSChatSession
# ----------------------------------------------------------------------------------------
class TSChatSession:
    """
    A multi-turn chat whose memory lives in the SDK.

    Creating one is free; the session opens in the SDK on the first call. ``close``
    (or leaving ``async with``) frees it.

    Parameters
    ----------
    llm: TSLLM
        The loaded model that answers.
    system_prompt: str, optional
        Instructions for the model. Default is the model's own.
    max_turns: int, optional
        Turns kept in memory (sliding window). Default is the SDK's.
    tools: list of Tool, optional
        Tools the model may call. The session runs the call, gives the model the
        result and streams its answer, all in one ``infer_stream``.

    Attributes
    ----------
    llm: TSLLM
    system_prompt: str or None
    max_turns: int or None
    tools: list of Tool
    """

    # Constructor
    # ------------------------------------------------------------------------------------
    def __init__(
        self,
        llm: TSLLM,
        system_prompt: str | None = None,
        max_turns: int | None = None,
        tools: list[Tool] | None = None,
    ):
        self.llm = llm
        self.system_prompt = system_prompt
        self.max_turns = max_turns
        self.tools = list(tools or [])
        self._handle: str | None = None
        self._relay: ToolRelay | None = None
        self._opening = asyncio.Lock()

    async def __aenter__(self) -> Self:
        return self

    async def __aexit__(self, *exc) -> None:
        await self.close()

    # Public Methods
    # ------------------------------------------------------------------------------------
    async def infer_stream(
        self,
        user_request: str,
        config: dict | None = None,
    ) -> AsyncIterator[LLMStreamEvent]:
        """
        Send the next user message and stream the reply.

        Parameters
        ----------
        user_request: str
            The user's message.
        config: dict, optional
            Overrides of the model's ``generation_defaults``, key by key:
            ``max_new_tokens``, ``min_new_tokens``, ``temperature``, ``top_k``,
            ``top_p``, ``min_p``, ``repetition_penalty``, ``seed``,
            ``enable_thinking``, ``stop_sequences``, ``speculative_decoding``.
            Keys left out keep the model's value.

        Yields
        ------
        event: LLMStreamEvent
            ``text_delta`` and ``thinking_delta`` as it decodes, ``tool_call`` /
            ``tool_result`` for tools the session runs, then ``final``.
        """
        stream, _ = await host().open_stream(
            "chat.infer_stream",
            chat=await self._open(),
            user_request=user_request,
            config=config or {},
        )
        async for frame in stream:
            yield LLMStreamEvent(frame.header["e"], frame.header.get("d", {}))

    async def infer(self, user_request: str, config: dict | None = None) -> str:
        """
        Send the next user message and return the whole reply.

        Parameters
        ----------
        user_request: str
            The user's message.
        config: dict, optional
            Overrides of the model's ``generation_defaults``, key by key:
            ``max_new_tokens``, ``min_new_tokens``, ``temperature``, ``top_k``,
            ``top_p``, ``min_p``, ``repetition_penalty``, ``seed``,
            ``enable_thinking``, ``stop_sequences``, ``speculative_decoding``.
            Keys left out keep the model's value.

        Returns
        -------
        text: str
            The reply text.
        """
        parts = []
        async for event in self.infer_stream(user_request, config):
            if event.kind == "text_delta":
                parts.append(event.text)
        return "".join(parts)

    async def history(self) -> list[dict]:
        """
        The conversation so far.

        Returns
        -------
        messages: list of dict
            ``{"role": "system" | "user" | "assistant" | "tool", "text": str,
            "parts": list of dict, "name": str}``.
        """
        frame = await host().call("chat.history", chat=await self._open())
        return frame.header["r"]["messages"]

    async def clear(self) -> None:
        """
        Forget the conversation (the system prompt stays).
        """
        if self._handle:
            await host().call("chat.clear", chat=self._handle)

    async def cancel_in_flight(self) -> None:
        """
        Stop the reply being generated; its stream ends.
        """
        if self._handle:
            await host().call("chat.cancel", chat=self._handle)

    async def close(self) -> None:
        """
        Free the session in the SDK. The next call starts a new, empty one.
        """
        handle, self._handle = self._handle, None
        self._relay = None
        if handle:
            await host().call("sdk.release", handle=handle)

    # Private Methods
    # ------------------------------------------------------------------------------------
    async def _open(self) -> str:
        """
        The session's handle, opening it in the SDK on first use.

        Returns
        -------
        handle: str
        """
        async with self._opening:
            if self._handle is None:
                frame = await host().call(
                    "chat.open",
                    llm=self.llm.handle,
                    system_prompt=self.system_prompt,
                    max_turns=self.max_turns,
                    tools=[tool.definition() for tool in self.tools] or None,
                )
                result = frame.header["r"]
                if "tools" in result:
                    self._relay = ToolRelay(host(), result["tools"], self.tools)
                self._handle = result["handle"]
            return self._handle
