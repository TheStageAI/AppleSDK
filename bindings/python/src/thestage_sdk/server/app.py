"""The aiohttp application: routes, auth, and errors in the OpenAI shape."""

from __future__ import annotations

import hmac
import logging

from aiohttp import web

from .._host import SDKError
from . import openai_audio, openai_chat, realtime, speech_stream
from .formats import SSE_RESPONSE, STREAM_RESPONSE, OpenAIError, sse_error
from .registry import ModelRegistry, ServerConfig

log = logging.getLogger("thestage_sdk.server")

# SDK error codes that mean the request was wrong, not the server.
_CLIENT_CODES = {"INVALID_PARAM", "MISSING_PARAM", "PROTOCOL"}


# ----------------------------------------------------------------------------------------
# Application
# ----------------------------------------------------------------------------------------
def create_app(
    config: ServerConfig, registry: ModelRegistry | None = None
) -> web.Application:
    """
    The server as an aiohttp application (for embedding; ``thestage-sdk serve``
    runs it).

    Parameters
    ----------
    config: ServerConfig
    registry: ModelRegistry, optional
        Default is a registry over ``config``.

    Returns
    -------
    app: aiohttp.web.Application
    """
    app = web.Application(
        middlewares=[_errors, _auth(config.api_key)], client_max_size=512 * 1024**2
    )
    app["config"] = config
    app["registry"] = registry or ModelRegistry(config)
    openai_chat.setup(app)
    openai_audio.setup(app)
    realtime.setup(app)
    speech_stream.setup(app)
    return app


# ----------------------------------------------------------------------------------------
# Middleware
# ----------------------------------------------------------------------------------------
@web.middleware
async def _errors(request: web.Request, handler):
    """
    Turn ``OpenAIError``, ``SDKError`` and unexpected exceptions into OpenAI-shaped
    error responses. After an SSE response has sent its headers the error goes
    in-band (an ``error`` event, then ``[DONE]``); another started stream is cut
    off.

    Parameters
    ----------
    request: aiohttp.web.Request
    handler: callable

    Returns
    -------
    response: aiohttp.web.StreamResponse
    """
    try:
        return await handler(request)
    except OpenAIError as error:
        failure = error
    except SDKError as error:
        status = 400 if error.code in _CLIENT_CODES else 500
        kind = "invalid_request_error" if status == 400 else "server_error"
        failure = OpenAIError(status, error.message, code=error.code.lower(), type=kind)
    except web.HTTPException:
        raise
    except Exception as error:  # the client gets a 500, the log the trace
        log.exception("request failed: %s %s", request.method, request.path)
        failure = OpenAIError(500, str(error), type="server_error")
    started = request.get(SSE_RESPONSE)
    if started is not None and started.prepared:
        log.warning("stream failed after headers: %s", failure)
        await sse_error(started, failure)
        return started
    started = request.get(STREAM_RESPONSE)
    if started is not None and started.prepared:
        # Raw audio has no in-band error: end the body short and drop the connection.
        log.warning("stream failed after headers: %s", failure)
        if request.transport is not None:
            request.transport.close()
        return started
    return failure.response()


def _auth(api_key: str | None):
    """
    The bearer-token check, or none when ``api_key`` is ``None``.

    WebSockets may send the subprotocol ``openai-insecure-api-key.<key>`` instead,
    as OpenAI's Realtime API accepts (browsers cannot set headers).

    Parameters
    ----------
    api_key: str or None

    Returns
    -------
    middleware: callable
    """

    @web.middleware
    async def middleware(request: web.Request, handler):
        if api_key is None or request.path == "/health":
            return await handler(request)
        given = request.headers.get("Authorization", "").removeprefix("Bearer ").strip()
        for protocol in request.headers.get("Sec-WebSocket-Protocol", "").split(","):
            protocol = protocol.strip()
            if protocol.startswith("openai-insecure-api-key."):
                given = protocol.removeprefix("openai-insecure-api-key.")
        if not hmac.compare_digest(given.encode(), api_key.encode()):
            return OpenAIError(
                401,
                "invalid API key",
                code="invalid_api_key",
                type="authentication_error",
            ).response()
        return await handler(request)

    return middleware
