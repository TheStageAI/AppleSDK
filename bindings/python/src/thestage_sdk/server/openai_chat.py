"""``/v1/models`` and ``/v1/chat/completions``.

A request carries the whole conversation; the SDK gets it as a message list
(``TSLLM.infer_events``), trimmed to the model's context. Images in a user
message route the request to the vision model. Tools come back to the client
as ``tool_calls``; the model's own text for each call is kept under the call's
id, so when the client sends the conversation back the model reads its turn
in its native format.
"""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import secrets
import time
from collections import OrderedDict
from pathlib import Path

import aiohttp
from aiohttp import web

from ..llm import LLMStreamEvent
from .formats import bad_request, sse_response, sse_send
from .registry import ModelRegistry, ServerConfig, split_speculative

log = logging.getLogger("thestage_sdk.server")

_LENGTH_STOPS = {"max_new_tokens", "length"}


# ----------------------------------------------------------------------------------------
# Routes
# ----------------------------------------------------------------------------------------
def setup(app: web.Application) -> None:
    """
    Register ``/v1/models``, ``/health`` and ``/v1/chat/completions``.

    Parameters
    ----------
    app: aiohttp.web.Application
    """
    app["raw_calls"] = RawCallCache()
    app.router.add_get("/v1/models", models)
    app.router.add_get("/health", health)
    app.router.add_post("/v1/chat/completions", chat_completions)


async def health(request: web.Request) -> web.Response:
    """
    Parameters
    ----------
    request: aiohttp.web.Request

    Returns
    -------
    response: aiohttp.web.Response
        ``{"status": "ok"}``; needs no API key.
    """
    return web.json_response({"status": "ok"})


async def models(request: web.Request) -> web.Response:
    """
    ``GET /v1/models``: the chat models, configured and loaded.

    Clients such as Open WebUI offer this list in their model picker, so it
    holds what answers text well: the language models. The vision model is
    listed only when no language model is configured — a message with an
    image reaches it from any chat model, and on text alone it mostly stops at
    once. The speech models stay off; the audio endpoints take their repo ids
    and OpenAI's names.

    Parameters
    ----------
    request: aiohttp.web.Request

    Returns
    -------
    response: aiohttp.web.Response
        ``{"object": "list", "data": [{"id", "object", "created", "owned_by",
        "kind"}]}``.
    """
    registry: ModelRegistry = request.app["registry"]
    data = [
        {
            "id": name,
            "object": "model",
            "created": 0,
            "owned_by": "thestage",
            "kind": kind,
        }
        for name, kind in registry.served()
        if kind == "llm" or (kind == "vlm" and registry.config.llm is None)
    ]
    return web.json_response({"object": "list", "data": data})


# ----------------------------------------------------------------------------------------
# Request to SDK
# ----------------------------------------------------------------------------------------
class RawCallCache:
    """
    The model's raw assistant text under each tool-call id it produced, so a
    conversation sent back reads the model's turn in its native format.

    Parameters
    ----------
    size: int
        Ids kept, newest first. Default is 1024.
    """

    # Constructor
    # ------------------------------------------------------------------------------------
    def __init__(self, size: int = 1024):
        self._items: OrderedDict[str, str] = OrderedDict()
        self._size = size

    # Public Methods
    # ------------------------------------------------------------------------------------
    def put(self, call_ids: list[str], raw: str) -> None:
        """
        Parameters
        ----------
        call_ids: list of str
            The ids minted for one assistant turn.
        raw: str
            That turn's text as the model wrote it.
        """
        for call_id in call_ids:
            self._items[call_id] = raw
            self._items.move_to_end(call_id)
        while len(self._items) > self._size:
            self._items.popitem(last=False)

    def get(self, call_id: str) -> str | None:
        """
        Parameters
        ----------
        call_id: str

        Returns
        -------
        raw: str or None
        """
        return self._items.get(call_id)


def _text(content) -> str:
    """
    Parameters
    ----------
    content: str, list of dict or None
        A message's ``content``.

    Returns
    -------
    text: str
        The text parts joined.
    """
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    return "".join(
        p.get("text", "") for p in content if p.get("type") in ("text", "input_text")
    )


async def _image(
    part: dict, session: aiohttp.ClientSession, config: ServerConfig | None = None
):
    """
    Parameters
    ----------
    part: dict
        An ``image_url`` content part.
    session: aiohttp.ClientSession
        For http(s) URLs.
    config: ServerConfig, optional
        ``allow_local_images``, ``image_fetch_timeout`` and ``image_max_bytes``;
        default ``ServerConfig()`` (no local files).

    Returns
    -------
    image: bytes or str
        The image's bytes (data or http URL) or a local path.

    Raises
    ------
    OpenAIError
        The URL could not be fetched or read, is too large, or names a local file
        while ``allow_local_images`` is off.
    """
    config = config or ServerConfig()
    url = (part.get("image_url") or {}).get("url", "")
    if url.startswith("data:"):
        return base64.b64decode(url.split(",", 1)[1])
    if url.startswith(("http://", "https://")):
        limit = config.image_max_bytes
        timeout = aiohttp.ClientTimeout(total=config.image_fetch_timeout)
        try:
            async with session.get(url, timeout=timeout) as response:
                if response.status != 200:
                    raise bad_request(
                        f"could not fetch image {url[:200]}: HTTP {response.status}"
                    )
                if (response.content_length or 0) > limit:
                    raise bad_request(f"image {url[:200]} is over {limit} bytes")
                data = bytearray()
                async for chunk in response.content.iter_chunked(1 << 16):
                    data += chunk
                    if len(data) > limit:
                        raise bad_request(f"image {url[:200]} is over {limit} bytes")
                return bytes(data)
        except (aiohttp.ClientError, asyncio.TimeoutError) as error:
            raise bad_request(f"could not fetch image {url[:200]}: {error!r}") from None
    if not config.allow_local_images:
        raise bad_request(
            f"image_url must be a data URL or http(s) URL: {url[:80]} "
            "(local files need the server's --allow-local-images)"
        )
    path = url.removeprefix("file://")
    if not Path(path).is_file():
        raise bad_request(
            f"image_url must be a data URL, http(s) URL or file: {url[:80]}"
        )
    return path


def _render_calls(calls: list[dict]) -> str:
    """
    Tool calls the server did not produce, in the common JSON-in-tags form.

    Parameters
    ----------
    calls: list of dict
        OpenAI ``tool_calls``.

    Returns
    -------
    text: str
    """
    return "\n".join(
        "<tool_call>\n"
        + json.dumps(
            {
                "name": c["function"]["name"],
                "arguments": json.loads(c["function"].get("arguments") or "{}"),
            }
        )
        + "\n</tool_call>"
        for c in calls
    )


async def conversation(
    body: dict, raw_calls: RawCallCache, config: ServerConfig | None = None
):
    """
    An OpenAI request's messages as the SDK takes them.

    Parameters
    ----------
    body: dict
        The request.
    raw_calls: RawCallCache
    config: ServerConfig, optional
        How ``image_url`` parts are read (see ``_image``).

    Returns
    -------
    system: str or None
        The ``system`` and ``developer`` messages joined.
    messages: list of dict
        ``{"role", "content", "name"}`` for ``TSLLM.infer_events``.
    images: list
        Bytes or paths from ``image_url`` parts.

    Raises
    ------
    OpenAIError
        Unknown roles, audio parts, or no messages.
    """
    system, messages, images = [], [], []
    call_names: dict[str, str] = {}
    async with aiohttp.ClientSession() as session:
        for m in body.get("messages") or []:
            role = m.get("role")
            if role in ("system", "developer"):
                system.append(_text(m.get("content")))
            elif role == "user":
                content = m.get("content")
                if isinstance(content, list):
                    for part in content:
                        if part.get("type") == "image_url":
                            images.append(await _image(part, session, config))
                        elif part.get("type") == "input_audio":
                            raise bad_request(
                                "audio in chat messages is not supported; "
                                "use /v1/audio/transcriptions",
                                param="messages",
                            )
                messages.append({"role": "user", "content": _text(content)})
            elif role == "assistant":
                calls = m.get("tool_calls") or []
                for c in calls:
                    call_names[c.get("id", "")] = c.get("function", {}).get("name", "")
                raw = next(
                    (
                        raw_calls.get(c.get("id", ""))
                        for c in calls
                        if raw_calls.get(c.get("id", ""))
                    ),
                    None,
                )
                text = raw or "\n".join(
                    filter(None, [_text(m.get("content")), _render_calls(calls)])
                )
                messages.append({"role": "assistant", "content": text})
            elif role == "tool":
                name = m.get("name") or call_names.get(m.get("tool_call_id", ""), "tool")
                messages.append(
                    {"role": "tool", "name": name, "content": _text(m.get("content"))}
                )
            else:
                raise bad_request(f"unknown role {role!r}", param="messages")
    if not messages:
        raise bad_request(
            "messages must hold at least one user message", param="messages"
        )
    return ("\n\n".join(system) or None), messages, images


def generation_config(body: dict) -> dict:
    """
    OpenAI sampling fields as the SDK's config keys; absent keys keep the model's
    defaults. Thinking is off unless ``reasoning_effort`` asks for it.

    Parameters
    ----------
    body: dict
        The request.

    Returns
    -------
    config: dict
    """
    config: dict = {}
    max_tokens = body.get("max_completion_tokens") or body.get("max_tokens")
    if max_tokens:
        config["max_new_tokens"] = int(max_tokens)
    for key in ("temperature", "top_p", "seed"):
        if body.get(key) is not None:
            config[key] = body[key]
    stop = body.get("stop")
    if stop:
        config["stop_sequences"] = [stop] if isinstance(stop, str) else list(stop)
    effort = body.get("reasoning_effort")
    config["enable_thinking"] = effort not in (None, "none", "minimal")
    return config


def _redacted(body: dict) -> str:
    """
    A request for the debug log, cut at 4000 characters.

    Parameters
    ----------
    body: dict

    Returns
    -------
    text: str
    """
    text = json.dumps(body, ensure_ascii=False)
    return text if len(text) < 4000 else text[:4000] + f"… ({len(text)} chars)"


def _tools(body: dict) -> list[dict] | None:
    """
    Parameters
    ----------
    body: dict
        The request.

    Returns
    -------
    tools: list of dict or None
        ``{"name", "description", "parameters"}``; ``None`` for no tools or
        ``tool_choice: "none"``.
    """
    if body.get("tool_choice") == "none":
        return None
    tools = [
        {
            "name": t["function"]["name"],
            "description": t["function"].get("description", ""),
            "parameters": t["function"].get("parameters") or {},
        }
        for t in body.get("tools") or []
        if t.get("type", "function") == "function"
    ]
    return tools or None


# ----------------------------------------------------------------------------------------
# Handler
# ----------------------------------------------------------------------------------------
async def chat_completions(request: web.Request) -> web.StreamResponse:
    """
    ``POST /v1/chat/completions``: one reply, or SSE chunks with ``stream``.

    Parameters
    ----------
    request: aiohttp.web.Request

    Returns
    -------
    response: aiohttp.web.StreamResponse
    """
    body = await request.json()
    log.debug("chat request: %s", _redacted(body))
    if body.get("n", 1) != 1:
        raise bad_request("n must be 1", param="n")
    registry: ModelRegistry = request.app["registry"]
    raw_calls: RawCallCache = request.app["raw_calls"]
    system, messages, images = await conversation(body, raw_calls, registry.config)
    config = generation_config(body)
    tools = _tools(body)

    # Images need the vision model; naming it also reaches it for plain text, as a
    # client's model picker offers it next to the chat model.
    names_vlm = body.get("model") is not None and body.get("model") == registry.config.vlm
    if images or names_vlm:
        if tools:
            raise bad_request(
                "tools with the vision model are not supported", param="tools"
            )
        # The picked chat model's name does not choose the vision model.
        model = await registry.get("vlm", body.get("model") if names_vlm else None)
        kind, name = "vlm", model.model_name
    else:
        # `<repo>:speculative`: the same model, decoding with its drafter. The drafter
        # runs only on greedy decoding, so the request's sampling gives way.
        requested, speculative = split_speculative(body.get("model"))
        model = await registry.get("llm", requested)
        if speculative:
            config.pop("top_p", None)
            config.update(speculative_decoding=True, temperature=0)
        kind, name = "llm", body.get("model") if speculative else model.model_name
    completion = Completion(name, raw_calls, tools=len(tools or []))

    async with registry.lock(model):
        if kind == "vlm":
            events = _vlm_events(model, images, messages, system, config)
        else:
            events = model.infer_events(
                messages, tools=tools, system_prompt=system, config=config
            )
        if body.get("stream"):
            include_usage = (body.get("stream_options") or {}).get("include_usage", False)
            return await completion.stream(request, events, include_usage)
        return web.json_response(await completion.collect(events))


async def _vlm_events(vlm, images, messages, system, config):
    """
    VLM chunks in the LLM event shape.

    Parameters
    ----------
    vlm: TSVLM
    images: list
    messages: list of dict
    system: str or None
    config: dict

    Yields
    ------
    event: LLMStreamEvent
        ``text_delta``, then ``final``.
    """
    async for chunk in vlm.infer_stream(
        images, messages=messages, system_prompt=system, config=config
    ):
        if chunk.is_final:
            yield LLMStreamEvent(
                "final",
                {
                    "stop_reason": chunk.stop_reason,
                    "prompt_tokens": chunk.prompt_tokens,
                    "generated_tokens": chunk.generated_tokens,
                },
            )
        elif chunk.text:
            yield LLMStreamEvent("text_delta", {"text": chunk.text})


# ----------------------------------------------------------------------------------------
# Completion
# ----------------------------------------------------------------------------------------
class Completion:
    """
    SDK events as one ``chat.completion`` or a ``chat.completion.chunk`` stream.

    Parameters
    ----------
    model: str
        The model name the response reports.
    raw_calls: RawCallCache
        Where the model's text for each tool call is kept.
    tools: int
        Tools in the request (for the empty-reply warning).
    """

    # Constructor
    # ------------------------------------------------------------------------------------
    def __init__(self, model: str, raw_calls: RawCallCache, tools: int = 0):
        self.id = "chatcmpl-" + secrets.token_hex(12)
        self.created = int(time.time())
        self.model = model
        self._raw_calls = raw_calls
        self._tools = tools
        self._call_ids: list[str] = []

    # Public Methods
    # ------------------------------------------------------------------------------------
    async def stream(
        self, request: web.Request, events, include_usage: bool
    ) -> web.StreamResponse:
        """
        Send the events as SSE chunks, then ``[DONE]``.

        Parameters
        ----------
        request: aiohttp.web.Request
        events: async iterator of LLMStreamEvent
        include_usage: bool
            Add the usage chunk (``stream_options.include_usage``).

        Returns
        -------
        response: aiohttp.web.StreamResponse
        """
        response = await sse_response(request)
        reason, usage = "stop", None
        try:
            await sse_send(response, self._chunk({"role": "assistant", "content": ""}))
            async for event in events:
                if event.kind == "text_delta" and event.text:
                    await sse_send(response, self._chunk({"content": event.text}))
                elif event.kind == "thinking_delta" and event.text:
                    await sse_send(
                        response, self._chunk({"reasoning_content": event.text})
                    )
                elif event.kind == "tool_call":
                    call = self._tool_call(event, len(self._call_ids))
                    await sse_send(response, self._chunk({"tool_calls": [call]}))
                elif event.kind == "final":
                    reason, usage = self._finish(event.data)
            await sse_send(response, self._chunk({}, reason))
            if include_usage:
                await sse_send(
                    response, {**self._chunk({}), "choices": [], "usage": usage}
                )
            await sse_send(response, "[DONE]")
        except ConnectionResetError:
            # The client left; finish the model's stream so the next request
            # does not start while this one still decodes.
            async for _ in events:
                pass
        return response

    async def collect(self, events) -> dict:
        """
        Gather the events into one response.

        Parameters
        ----------
        events: async iterator of LLMStreamEvent

        Returns
        -------
        completion: dict
            A ``chat.completion`` object.
        """
        text, thinking, calls = [], [], []
        reason, usage = "stop", None
        async for event in events:
            if event.kind == "text_delta":
                text.append(event.text)
            elif event.kind == "thinking_delta":
                thinking.append(event.text)
            elif event.kind == "tool_call":
                call = self._tool_call(event, len(calls))
                call.pop("index")
                calls.append(call)
            elif event.kind == "final":
                reason, usage = self._finish(event.data)
        message: dict = {"role": "assistant", "content": "".join(text) or None}
        if thinking:
            message["reasoning_content"] = "".join(thinking)
        if calls:
            message["tool_calls"] = calls
        return {
            "id": self.id,
            "object": "chat.completion",
            "created": self.created,
            "model": self.model,
            "choices": [{"index": 0, "message": message, "finish_reason": reason}],
            "usage": usage,
        }

    # Private Methods
    # ------------------------------------------------------------------------------------
    def _tool_call(self, event, index: int) -> dict:
        """
        Parameters
        ----------
        event: LLMStreamEvent
            A ``tool_call`` event.
        index: int
            Its position in the turn.

        Returns
        -------
        call: dict
            An OpenAI tool call with a new ``call_…`` id.
        """
        call_id = "call_" + secrets.token_hex(12)
        self._call_ids.append(call_id)
        return {
            "index": index,
            "id": call_id,
            "type": "function",
            "function": {
                "name": event.data.get("name", ""),
                "arguments": json.dumps(event.data.get("arguments") or {}),
            },
        }

    def _finish(self, final: dict) -> tuple[str, dict]:
        """
        Parameters
        ----------
        final: dict
            The ``final`` event's data.

        Returns
        -------
        finish_reason: str
            ``tool_calls``, ``length`` or ``stop``.
        usage: dict
        """
        if self._call_ids:
            self._raw_calls.put(self._call_ids, final.get("raw_text") or "")
            reason = "tool_calls"
        elif final.get("stop_reason") in _LENGTH_STOPS:
            reason = "length"
        else:
            reason = "stop"
        prompt = final.get("prompt_tokens") or 0
        generated = final.get("generated_tokens") or 0
        if not generated and not self._call_ids:
            # Usually a prompt the model's context cannot hold: a client's long
            # system prompt or many tools (Open WebUI's built-in tools).
            log.warning(
                "empty reply from %s: prompt %d tokens, %d tools in the request",
                self.model,
                prompt,
                self._tools,
            )
        usage = {
            "prompt_tokens": prompt,
            "completion_tokens": generated,
            "total_tokens": prompt + generated,
        }
        return reason, usage

    def _chunk(self, delta: dict, finish_reason: str | None = None) -> dict:
        """
        Parameters
        ----------
        delta: dict
        finish_reason: str, optional

        Returns
        -------
        chunk: dict
            A ``chat.completion.chunk``.
        """
        return {
            "id": self.id,
            "object": "chat.completion.chunk",
            "created": self.created,
            "model": self.model,
            "choices": [{"index": 0, "delta": delta, "finish_reason": finish_reason}],
        }
