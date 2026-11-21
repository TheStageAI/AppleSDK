"""Tools the model can call, written in Python.

A ``Tool`` is a JSON Schema the model sees and the function that runs when the model
calls it. ``TSChatSession(tools=…)`` and ``TSVoiceAgent.create(tools=…)`` run the tool
loop in the SDK: the model calls, your function runs, its result goes back to the model,
and the answer arrives on the same stream::

    async def get_weather(arguments: dict) -> dict:
        return {"city": arguments["city"], "temp_c": 21}

    weather = Tool(
        name="get_weather",
        description="Current weather for a city.",
        parameters={
            "type": "object",
            "properties": {"city": {"type": "string"}},
            "required": ["city"],
        },
        execute=get_weather,
    )
"""

from __future__ import annotations

import asyncio
import inspect
import json
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from typing import Any

from ._host import Host, SDKError


# ----------------------------------------------------------------------------------------
# Tool
# ----------------------------------------------------------------------------------------
@dataclass
class Tool:
    """
    One tool: what the model sees and what runs when it calls it.

    Attributes
    ----------
    name: str
        The name the model calls it by.
    description: str
        When to use it; the model reads this.
    parameters: dict
        JSON Schema of the arguments, e.g. ``{"type": "object", "properties":
        {"city": {"type": "string"}}, "required": ["city"]}``.
    execute: callable or None
        ``(arguments: dict) -> str | dict | list``, plain or ``async``. A plain
        function runs in a worker thread so it cannot stall the event loop. A
        ``str`` result goes to the model as is, anything else as JSON. ``None``
        returns the SDK's placeholder result (for trying a prompt).
    """

    # Public Attributes
    # ------------------------------------------------------------------------------------
    name: str
    description: str
    parameters: dict = field(default_factory=dict)
    execute: Callable[[dict], Any] | Callable[[dict], Awaitable[Any]] | None = None

    # Public Methods
    # ------------------------------------------------------------------------------------
    def definition(self) -> dict:
        """
        The tool as the bridge sends it.

        Returns
        -------
        definition: dict
            ``name``, ``description``, ``parameters`` and ``callback`` (whether
            ``execute`` runs in Python).
        """
        return {
            "name": self.name,
            "description": self.description,
            "parameters": self.parameters,
            "callback": self.execute is not None,
        }

    async def run(self, arguments: dict) -> str:
        """
        Run ``execute`` and turn its result into the text the model reads.

        Parameters
        ----------
        arguments: dict
            The arguments the model sent.

        Returns
        -------
        content: str
        """
        if inspect.iscoroutinefunction(self.execute):
            result = await self.execute(arguments)
        else:
            result = await asyncio.to_thread(self.execute, arguments)
            if inspect.isawaitable(result):
                result = await result
        return result if isinstance(result, str) else json.dumps(result, default=str)


# ----------------------------------------------------------------------------------------
# ToolRelay
# ----------------------------------------------------------------------------------------
class ToolRelay:
    """
    Answers the SDK's tool calls for one session or agent until the SDK closes it.

    A tool that raises answers ``{"error": "<Type>: <message>"}``, so the model can
    tell the user it failed; an unknown name answers the same way.

    Parameters
    ----------
    host: Host
    handle: str
        The relay the SDK returned (``tools`` in the open call's result).
    tools: list of Tool
    """

    # Constructor
    # ------------------------------------------------------------------------------------
    def __init__(self, host: Host, handle: str, tools: list[Tool]):
        self.handle = handle
        self._host = host
        self._tools = {tool.name: tool for tool in tools}
        self._calls: set[asyncio.Task] = set()
        self._task = asyncio.create_task(self._serve(host.attach_stream(handle)))

    # Private Methods
    # ------------------------------------------------------------------------------------
    async def _serve(self, stream) -> None:
        """
        Start one answer per ``call`` event, until the stream ends.

        Parameters
        ----------
        stream: Stream
        """
        try:
            async for frame in stream:
                if frame.header.get("e") == "call":
                    task = asyncio.create_task(self._answer(frame.header.get("d", {})))
                    self._calls.add(task)
                    task.add_done_callback(self._calls.discard)
        except SDKError:
            pass

    async def _answer(self, call: dict) -> None:
        """
        Run one call and send its result.

        Parameters
        ----------
        call: dict
            ``id``, ``name``, ``arguments``.
        """
        tool = self._tools.get(call.get("name"))
        try:
            if tool is None:
                raise LookupError(f"no tool named {call.get('name')!r}")
            content = await tool.run(call.get("arguments") or {})
        # Any failure of user code goes to the model, which tells the user; the turn
        # goes on instead of ending in an error.
        except Exception as error:  # noqa: BLE001
            content = json.dumps({"error": f"{type(error).__name__}: {error}"})
        try:
            await self._host.call(
                "tools.result", relay=self.handle, id=call["id"], content=content
            )
        except SDKError:
            pass  # the session or agent closed while the tool ran
