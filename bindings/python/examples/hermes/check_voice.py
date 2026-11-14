"""Run Hermes's own speech tools against the local server: speak a sentence, then
transcribe the file back.

    thestage-sdk serve
    HERMES_HOME=~/.hermes python check_voice.py     # with Hermes installed in this env
"""

import os
import sys
import tempfile
from pathlib import Path

from tools.transcription_tools import transcribe_audio
from tools.tts_tool import text_to_speech_tool

SENTENCE = "Hermes is speaking through TheStage on this Mac."


def main() -> int:
    # The `hermes` command loads ~/.hermes/.env at startup; a bare import does not.
    os.environ.setdefault("VOICE_TOOLS_OPENAI_KEY", "local")
    path = Path(tempfile.mkdtemp()) / "hermes_check.mp3"
    spoken = text_to_speech_tool(SENTENCE, output_path=str(path))
    if '"success": true' not in spoken:
        print("text-to-speech failed:", spoken)
        return 1
    print(f"text-to-speech: {path.stat().st_size} bytes of mp3")

    heard = transcribe_audio(str(path))
    if not heard.get("success"):
        print("speech-to-text failed:", heard.get("error"))
        return 1
    print("speech-to-text:", heard["transcript"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
