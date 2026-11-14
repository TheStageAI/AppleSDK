# Hermes Agent with TheStage voice

[Hermes Agent](https://hermes-agent.nousresearch.com) speaks and listens through the local
server: text-to-speech and speech-to-text run on this Mac's Neural Engine.

1. Start the server: `thestage-sdk serve` (add `--api-key` if Hermes runs on another
   machine, and use that key below instead of `local`).
2. Merge [config.yaml](config.yaml) into `~/.hermes/config.yaml`.
3. Append [env.example](env.example) to `~/.hermes/.env`.
4. Check: `python check_voice.py` in the Python environment Hermes is installed in.

Expected output:

```
text-to-speech: 21120 bytes of mp3        (the size varies a little)
speech-to-text: Hermes is speaking through the stage on this Mac.
```

What works and what does not (Hermes 0.19.0, checked 2026-10-19):

| Part | State |
|---|---|
| Speech-to-text (`stt.openai.base_url`) | Works. Hermes asks for `response_format="text"`, which the server serves |
| Text-to-speech (`tts.openai.base_url`) | Works for the CLI and every platform that takes mp3 |
| Telegram voice bubbles | Not yet: Hermes asks for Ogg/Opus there, which the server does not produce |
| Chat model | Not on device: Hermes requires 64K tokens of context and sends about 12K before the conversation (7.6 KB of system prompt, 38.7 KB of tool schemas); the on-device packs hold 1,256 |

`stt.openai.api_key` must be set for Hermes to use `stt.openai.base_url` (any value);
without it Hermes falls back to OpenAI's own URL. Hermes's docs do not list the STT
`base_url` key; it is in `tools/transcription_tools.py`.
