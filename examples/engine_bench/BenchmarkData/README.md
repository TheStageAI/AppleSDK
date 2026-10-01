# Local benchmark datasets

LLM Benchmark selects Canon100, Extended320, or Agentic/BFCL96 from Scion's frozen 2026-09-07 token sets. Agentic/BFCL96 is the default. The app uses stored token IDs only after checking the LFM tokenizer hash; incompatible tokenizers fail explicitly. EOS is enabled; the UI's max-token setting remains effective (default64). Runs means repetitions per prompt. Rates and tau are means of per-prompt means. The JSON export retains source domains, per-prompt timings and stop reasons. These private held-out token files remain gitignored.

ASR Benchmark offers a language picker: All (default) runs50 files; an individual language runs its5files. The complete pack contains50 FLEURS test WAVs,10languages ×5files, from asr_multilingual50.json. Language is forced from each manifest row. Each file has an untimed warmup, then the UI's repetition count (default2). Rates and tau are means of per-file means, with aggregate and per-language rows. RTFx includes full warm inference but excludes WAV reading and model loading; tok/s excludes prefill. JSON includes clip/language, tokens, cycle counts, prefill/encode timing and warmup token-parity flags. Developer --bench-self-test uses one file per language; it does not alter the normal UI's50-file benchmark.

Prepare locally before building (paths are examples; use the original downloaded inputs):

```sh
python3 prepare_benchmark_data.py \
  --asr-manifest /absolute/path/to/asr-multilingual-2026-09-06/data/manifest.json \
  --scion-directory "$HOME/Downloads/scionpromptsets20260907"
```

The script validates WAV hashes and token counts and copies inputs into the app folder. WAVs live in ignored BenchmarkData/asr_fixtures; private Scion JSONs in ignored BenchmarkData/scion. The old smoke8.jsonl is retained as a historical fixture and is no longer used by the Benchmark button.

Models are downloaded from their HF repositories (LFM230/350 and Qwen-ASR use spec_dec). Benchmark fixtures remain local in BenchmarkData. No model weights are bundled and no upload occurs during app builds or tests.
