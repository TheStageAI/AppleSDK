"""Shared setup for the examples: the API token from the environment."""

import os

import thestage_sdk as ts


async def initialize() -> None:
    """``THESTAGE_API_TOKEN`` is required; ``HF_TOKEN`` only for gated repos."""
    await ts.initialize(
        api_token=os.environ["THESTAGE_API_TOKEN"],
        hf_token=os.environ.get("HF_TOKEN"),
    )
