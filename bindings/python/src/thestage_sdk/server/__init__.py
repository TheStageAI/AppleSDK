"""An OpenAI-compatible server over the SDK (``pip install 'thestage_sdk[server]'``).

``thestage-sdk serve`` runs it; ``create_app`` builds the aiohttp application
for embedding. See ``docs/server.md``.
"""

from .app import create_app
from .registry import ModelRegistry, ServerConfig

__all__ = ["ModelRegistry", "ServerConfig", "create_app"]
