"""Frames between Python and ``thestage-host``.

One frame::

    u32 BE  length of everything after this field
    u32 BE  header length
    header  UTF-8 JSON object
    body    raw bytes (little-endian float32 PCM, or empty)

The header kinds and keys are documented in the Swift ``BridgeFrame``.
Audio is the body, never JSON numbers, so a chunk maps straight into a
NumPy array without parsing.
"""

from __future__ import annotations

import json
import struct
from dataclasses import dataclass, field

import numpy as np

# ----------------------------------------------------------------------------------------
# Frame
# ----------------------------------------------------------------------------------------
_U32 = struct.Struct(">I")


@dataclass
class Frame:
    # Public Attributes
    # ------------------------------------------------------------------------------------
    """
    One message between Python and ``thestage-host``.

    Attributes
    ----------
    header: dict
        The JSON header: ``t`` (kind), ``id``, ``m`` (method), ``p`` (params),
        ``r`` (result), ``s`` (stream), ``e`` (event or error), ``d`` (data).
    body: bytes
        Raw bytes: little-endian float32 PCM, encoded images, or empty.
    """

    header: dict
    body: bytes = field(default=b"")

    # Public Methods
    # ------------------------------------------------------------------------------------
    def encode(self) -> bytes:
        """
        The frame on the wire.

        Returns
        -------
        data: bytes
            u32 BE length, u32 BE header length, JSON header, body.
        """
        head = json.dumps(self.header, separators=(",", ":")).encode()
        return (
            _U32.pack(4 + len(head) + len(self.body))
            + _U32.pack(len(head))
            + head
            + self.body
        )

    @property
    def pcm(self) -> np.ndarray:
        """
        The body as float32 samples (a view, no copy).

        Returns
        -------
        samples: numpy.ndarray
        """
        return np.frombuffer(self.body, dtype="<f4")


# ----------------------------------------------------------------------------------------
# Reading and writing
# ----------------------------------------------------------------------------------------
def pcm_body(samples) -> bytes:
    """
    Samples as a frame body.

    Parameters
    ----------
    samples: array-like
        Any 1-D sequence of samples.

    Returns
    -------
    body: bytes
        Little-endian float32.
    """
    return np.ascontiguousarray(samples, dtype="<f4").tobytes()


async def read_frame(reader) -> Frame:
    """
    The next frame from the host.

    Parameters
    ----------
    reader: asyncio.StreamReader

    Returns
    -------
    frame: Frame
    """
    (length,) = _U32.unpack(await reader.readexactly(4))
    payload = await reader.readexactly(length)
    (head_length,) = _U32.unpack(payload[:4])
    header = json.loads(payload[4 : 4 + head_length])
    return Frame(header=header, body=payload[4 + head_length :])
