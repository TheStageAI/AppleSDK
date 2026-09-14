# tutor_small_llms

The example behind the tutorial *Apple SDK: turn a receipt, chat, or SMS
into structured data on device*. Runs five guides on one pack and prints
what the model returned and what the app parsed from it.

```bash
export TS_API_TOKEN=th_…
PACK=qwen06 GUIDE=1,2,3,4,5 swift run -c release
```

- `PACK` — `lfm230` | `lfm350` | `qwen06` | `gemma1b` (default `lfm350`)
- `GUIDE` — any subset of `1,2,3,4,5`: receipt · calendar · pickup code ·
  share-sheet router · tools
- `LLM_BUNDLE` — a local bundle path instead of the Hugging Face id

Guides 1–4 decode greedily (repeatable extraction); guide 5 uses the
vendor's sampling card (chat). `recipes.swift` holds the prompts,
`normalize.swift` the app-side date / time normaliser.
