# Vision-language models

[Docs home](README.md) · [Language models](llm.md) · [Speech recognition](asr.md) ·
[Microphone and audio](audio.md) · [Text to speech](tts.md) · [Voice agent](voice_agent.md) ·
[Server](server.md)

Ask questions about images: describe a photo, read a receipt, compare screenshots.

```python
import thestage_sdk as ts

vlm = await ts.TSVLM.load(
    "TheStageAI/LFM2.5-VL-450M",
    model_name=None,           # the name to unload it by; default: the repo id
    device="npu",              # "npu" (default), "gpu" or "cpu"
)

result = await vlm.infer(
    ["photo.jpg"],                              # images
    "Describe this image in two sentences.",
    system_prompt=None,                         # optional
    config={"max_new_tokens": 128},             # same keys as the language model config
)
result.text, result.prompt_tokens, result.generated_tokens
```

Images can be given as:

| Form | Example |
|---|---|
| A path | `"photo.jpg"`, `pathlib.Path("scan.heic")` |
| Encoded bytes (JPEG, PNG, HEIC) | `open("receipt.png", "rb").read()` |
| A PIL image | `PIL.Image.open("x.png")`, or a screenshot from `PIL.ImageGrab.grab()` |

Paths are read by the SDK; bytes and PIL images travel with the call. When order matters
("compare the first and the second"), give all images in one form.

**Streamed.**

```python
async for chunk in vlm.infer_stream([open("receipt.png", "rb").read()], "What is the total?"):
    print(chunk.text, end="", flush=True)
```

**A conversation about the images.** Pass `messages` instead of a prompt:

```python
async for chunk in vlm.infer_stream(
    ["before.png", "after.png"],
    messages=[
        {"role": "system", "content": "You compare UI screenshots."},
        {"role": "user", "content": "What changed between the two screens?"},
    ],
):
    print(chunk.text, end="")
```

`config` takes the [language model keys](llm.md#generation-settings-config); the chunks
are `LLMStreamChunk`s. The [local server](server.md) routes chat messages with images to
the vision model, so OpenAI clients can send images too.

## Runnable examples

- [`examples/vlm_describe.py`](../examples/vlm_describe.py): describe an image by path and by bytes
