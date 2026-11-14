"""Check Open WebUI end to end on TheStage models, through Open WebUI's own API:
its model list, a streamed chat reply, read-aloud and dictation.

    python check.py                       # Open WebUI at http://127.0.0.1:8080
    python check.py http://127.0.0.1:3000

Needs a running ``thestage-sdk serve``, Open WebUI started with ``openwebui.env``,
and ffmpeg (for the dictation check). Standard library only.
"""

import json
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import uuid
from pathlib import Path


# ----------------------------------------------------------------------------------------
# Open WebUI API
# ----------------------------------------------------------------------------------------
def request(url: str, token: str | None = None, body=None, headers=None):
    """
    One HTTP call.

    Parameters
    ----------
    url: str
    token: str, optional
        Open WebUI's bearer token.
    body: dict or bytes, optional
        JSON for a dict, raw bytes otherwise; ``None`` makes a GET.
    headers: dict, optional

    Returns
    -------
    response: http.client.HTTPResponse
    """
    headers = dict(headers or {})
    data = body
    if isinstance(body, dict):
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return urllib.request.urlopen(urllib.request.Request(url, data, headers), timeout=300)


def multipart(name: str, data: bytes, content_type: str) -> tuple[bytes, str]:
    """
    One file as multipart/form-data.

    Parameters
    ----------
    name: str
        The file name.
    data: bytes
    content_type: str
        What a browser would send, e.g. ``audio/webm``.

    Returns
    -------
    body: bytes
    header: str
        The Content-Type header with the boundary.
    """
    boundary = uuid.uuid4().hex
    head = (
        f'--{boundary}\r\nContent-Disposition: form-data; name="file"; '
        f'filename="{name}"\r\nContent-Type: {content_type}\r\n\r\n'
    )
    body = head.encode() + data + f"\r\n--{boundary}--\r\n".encode()
    return body, f"multipart/form-data; boundary={boundary}"


# ----------------------------------------------------------------------------------------
# Checks
# ----------------------------------------------------------------------------------------
def main(base: str) -> int:
    """
    Run the checks.

    Parameters
    ----------
    base: str
        Open WebUI's address.

    Returns
    -------
    code: int
        0 when every check passes.
    """
    with request(f"{base}/api/v1/auths/signin", body={"email": "", "password": ""}) as r:
        token = json.load(r)["token"]  # WEBUI_AUTH=False signs in the local user

    with request(f"{base}/api/models?refresh=true", token) as r:
        listed = json.load(r)["data"]
    models = [m["id"] for m in listed]
    print("models:", models)
    if not models:
        print("no models: is thestage-sdk serve running at OPENAI_API_BASE_URL?")
        return 1
    for m in listed:
        capabilities = (m.get("info") or {}).get("meta", {}).get("capabilities") or {}
        if capabilities.get("builtin_tools", True):
            print(
                f"warning: built-in tools are on for {m['id']}: browser chats will get "
                "empty replies (see README, 'Empty replies')"
            )

    chat = {
        "model": models[0],
        "messages": [{"role": "user", "content": "Say hello in five words."}],
        "stream": True,
    }
    reply = ""
    with request(f"{base}/api/chat/completions", token, chat) as r:
        for line in r:
            line = line.decode().strip()
            if line.startswith("data: ") and line != "data: [DONE]":
                choices = json.loads(line[6:]).get("choices") or [{}]
                reply += choices[0].get("delta", {}).get("content") or ""
    print("chat:", reply.strip())

    speech = {"input": "Open WebUI is speaking through TheStage on this Mac."}
    with request(f"{base}/api/v1/audio/speech", token, speech) as r:
        audio, kind = r.read(), r.headers.get("Content-Type")
    print(f"read aloud: {len(audio)} bytes of {kind}")

    if not shutil.which("ffmpeg"):
        print("dictation: skipped (install ffmpeg; Open WebUI needs it for recordings)")
        return 0
    folder = Path(tempfile.mkdtemp())
    (folder / "speech.mp3").write_bytes(audio)
    subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-y", "-i", str(folder / "speech.mp3"),
         "-c:a", "libopus", str(folder / "recording.webm")],
        check=True,
    )  # fmt: skip
    body, content_type = multipart(
        "recording.webm", (folder / "recording.webm").read_bytes(), "audio/webm"
    )
    url = f"{base}/api/v1/audio/transcriptions"
    with request(url, token, body, {"Content-Type": content_type}) as r:
        print("dictation:", json.load(r)["text"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8080"))
