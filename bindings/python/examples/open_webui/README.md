# Open WebUI on TheStage models

[Open WebUI](https://openwebui.com) chats, takes dictation and reads replies aloud on
TheStage models running on this Mac, through the local OpenAI-compatible server.

1. Start the server: `thestage-sdk serve --llm all` (port 8000). `--llm all` puts every
   shipped chat model in Open WebUI's picker; a plain `thestage-sdk serve` offers only
   `TheStageAI/Qwen3-0.6B`.
2. Start Open WebUI with [openwebui.env](openwebui.env). Open WebUI needs Python 3.11 and
   ffmpeg; with uv no install step is needed:

   ```bash
   brew install ffmpeg            # Open WebUI converts browser recordings with it
   set -a; source openwebui.env; set +a
   uvx --python 3.11 open-webui serve --host 127.0.0.1 --port 8080
   ```

   Keep `--host 127.0.0.1`: Open WebUI listens on every interface by default, and with
   `WEBUI_AUTH=False` anyone on the network could use it.

3. Open http://127.0.0.1:8080. Chat with the model, press the microphone to dictate, and
   the speaker icon under a reply to hear it.
4. Check from a terminal: `python check.py` (standard library only).

Expected output:

```
models: ['TheStageAI/Qwen3-0.6B']
chat: Hello! How can I assist you today?
read aloud: 29184 bytes of audio/mpeg      (the size varies)
dictation: Open Web UI is speaking through the stage on this Mac.
```

What was checked (Open WebUI from PyPI, 2026-10-19):

| Part | State |
|---|---|
| Model list | The chat models given with `--llm` (the speech models stay off the picker); picking another unloads the last. Models with a drafter also appear as `…:speculative`: faster on Gemma 4 E2B, greedy (temperature ignored) |
| Chat, streamed | Works; emoji and other multi-byte characters arrive whole |
| Read aloud (`AUDIO_TTS_ENGINE=openai`) | Works; mp3 |
| Dictation (`AUDIO_STT_ENGINE=openai`) | Works for WebM/Opus (browser) and M4A: Open WebUI converts them to mp3 with ffmpeg first |
| Images in chat | Start the server with `--vlm TheStageAI/LFM2.5-VL-450M`; attach an image in any chat and it goes to the vision model (the picker shows only the chat model) |
| Voice call mode (OpenAI Realtime) | Not supported: the server's Realtime endpoint does transcription only |

## Empty replies in the browser

Open WebUI adds its built-in tools (time, memory, knowledge bases, …) to every chat sent
from the browser. Their schemas alone are more than Qwen3-0.6B's 1,256-token context, so
the reply comes back empty, and with nothing to read, read-aloud stays silent too. API
calls (and `check.py`'s chat) do not get the tools, which is why they work.

`openwebui.env` turns them off for a new install (`DEFAULT_MODEL_METADATA`). Open WebUI
keeps its settings in its database after the first start, so for an existing install
either set it once as admin through the API:

```bash
TOKEN=$(curl -s -X POST http://127.0.0.1:8080/api/v1/auths/signin \
    -H 'Content-Type: application/json' -d '{"email":"","password":""}' \
    | python3 -c "import json,sys;print(json.load(sys.stdin)['token'])")
curl -s http://127.0.0.1:8080/api/v1/configs/models -H "Authorization: Bearer $TOKEN" \
    | python3 -c "import json,sys;c=json.load(sys.stdin);c['DEFAULT_MODEL_METADATA']={'capabilities':{'builtin_tools':False}};print(json.dumps(c))" \
    | curl -s -X POST http://127.0.0.1:8080/api/v1/configs/models \
        -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d @-
```

or turn off "Builtin Tools" in Workspace → Models → the model → Capabilities. `check.py`
warns while they are on; the server logs `empty reply … tools in the request` when it
happens.

The on-device chat model's context is short (Qwen3-0.6B: 1,256 tokens); long chats keep
the newest turns. With Docker, point the URLs in `openwebui.env` at
`http://host.docker.internal:8000/v1`.
