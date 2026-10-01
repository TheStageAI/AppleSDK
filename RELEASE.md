# TheStage Apple SDK 1.5.0

Built 2026-10-01. Pin this tag; the examples use `exact: Version(1, 5, 0)`.

## Binary

| slice | sha256 |
|---|---|
| `ios-arm64` | `c33ebad78d35ee660e891f43b93c462c8a45b1f7d6647e3946cd9fc6fd25afb7` |
| `macos-arm64` | `35d9a18cb3044a977a8cbaa07aa8d3a1a9ee9e4c27f9120ad181f0fb9319d280` |

## Models

Every repo the SDK resolves by default, at the revision this build pins. The
sha256 is of the `.thestage` pack on Hugging Face.

| model | repo | revision | pack sha256 | size |
|---|---|---|---|---|
| `qwen3-0.6b` | `TheStageAI/Qwen3-0.6B` | `v1.4` | `83995f666e3abec5ccdeea85dbfd4271f655407c4c0f417f69099dcbb5b5eed4` | 435.9 MB |
| `gemma3-1b-it` | `TheStageAI/gemma-3-1b-it` | `v1.4` | `76f21a3b0af85ccec57c007abada77638a668eefc22021c0be1d69e1b4553dd4` | 760.8 MB |
| `lfm2.5-230m-compact` | `TheStageAI/LFM2.5-230M` | `v1.5` | `ae8c8933952b33bdc8975c7553e14d9d829fa07a6d45b91952091bf96953a613` | 230.1 MB |
| `lfm2.5-350m-compact` | `TheStageAI/LFM2.5-350M` | `v1.5` | `40e9b39e34aeb981a2010f5ee1a9c36e291afc7a94216b1271ebe5ff140e0ec9` | 293.1 MB |
| `lfm2.5-1.2b-compact` | `TheStageAI/LFM2.5-1.2B` | `v1.5` | `09160e04801e159187e143243f6802441344ce81e41ac05ad91e995c5af60744` | 919.7 MB |
| `thewhisper-large-v3-turbo` | `TheStageAI/thewhisper-large-v3-turbo` | `v1.4` | `25122345c95566e1053d2a1d5e07d51543274bd2873fb955f03feb2c0f2df7ad` | 569.0 MB |
| `qwen3-asr-0.6b-dflash2` | `TheStageAI/Qwen3-ASR-0.6B` | `v1.5` | `bd061f97c3be781fa5a50a7d7f93434875fc097629d9f1127a57e4d606a2a944` | 645.5 MB |
| `parakeet-tdt-0.6b-v3` | `TheStageAI/parakeet-tdt-0.6b-v3` | `v1.4` | `2a1064b8b99eeab173847e40e757c00e6fcc1914f2ed56eea81397218cfb9d20` | 250.0 MB |
| `neutts-nano-multilingual` | `TheStageAI/neutts-nano-multilingual` | `v1.4` | `f7a0f92f3617715915f62f28e8fc754585f2d4a8921e4245034a0046a5db486c` | 248.1 MB |
| `qwen3-tts-12hz-0.6b-base` | `TheStageAI/Qwen3-TTS-12Hz-0.6B-Base` | `v1.4` | `0351b57d097ba76fd67948422cc97df4a299ec138b9a3e1290d050a5fd7ca8a6` | 633.5 MB |
| `silero-vad` | `TheStageAI/silero-vad` | `v1.4` | `71bb26577c55b4a697e4513d95d9995468df22d3f68fcdbd5e2c26f59cf8ed8e` | 0.7 MB |
| `smart-turn-v3` | `TheStageAI/smart-turn-v3` | `v1.4` | `2b457ffbf1996313bc4969a0d3f256dbaca978556df286ef11fefdb37f23766a` | 8.9 MB |
| `redimnet2` | `TheStageAI/redimnet2` | `v1.4` | `1dde738b10643ce6fc6c8ca1921067a59f575134fd0259070482a39b047e17b5` | 3.7 MB |
| `speaker-segmentation` | `TheStageAI/speaker-segmentation` | `v1.4` | `9149e420fe489220b65bf1c11e541e15b698b17c8f4939bb0ebce127a50c32f7` | 3.0 MB |
| `lfm2.5-vl-450m` | `TheStageAI/LFM2.5-VL-450M` | `v1.2` | `49f7aadd733e8cf8101889ece77b11bfb9465dbb9a8c0a4e1e2dc1ed713920fe` | 273.2 MB |
| `gemma4-e2b-it` | `TheStageAI/gemma-4-E2B-it` | `v1.5` | `6158db8b7b55901815e57721d346fe461a051c1debc7a4c7f5da7ae55ad11369` | 1,770.6 MB |

## Verify

```bash
shasum -a 256 TheStageCore.xcframework/ios-arm64/TheStageCore.framework/TheStageCore
```
