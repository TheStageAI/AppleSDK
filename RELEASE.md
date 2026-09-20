# TheStage Apple SDK 1.4.1

Built 2026-09-19. Pin this tag; the examples use `exact: Version(1, 4, 1)`.

## Binary

| slice | sha256 |
|---|---|
| `ios-arm64` | `451a77bddefd4b2df011dfc1053d11bc748a9b8cadb2709c0f853eaa3d46fbd6` |
| `macos-arm64` | `43bfc405633f8088cc588867a2ace3666f72d670228a0978f941c25bf24cc6dc` |

## Models

Every repo the SDK resolves by default, at the revision this build pins. The
sha256 is of the `.thestage` pack on Hugging Face.

| model | repo | revision | pack sha256 | size |
|---|---|---|---|---|
| `qwen3-0.6b` | `TheStageAI/Qwen3-0.6B` | `v1.4` | `83995f666e3abec5ccdeea85dbfd4271f655407c4c0f417f69099dcbb5b5eed4` | 435.9 MB |
| `gemma3-1b-it` | `TheStageAI/gemma-3-1b-it` | `v1.4` | `76f21a3b0af85ccec57c007abada77638a668eefc22021c0be1d69e1b4553dd4` | 760.8 MB |
| `lfm2.5-230m` | `TheStageAI/LFM2.5-230M` | `v1.4` | `a9a9df28b5e02907ead8fff0720388571153999c212e4867dc08210dbcca8e33` | 178.5 MB |
| `lfm2.5-350m` | `TheStageAI/LFM2.5-350M` | `v1.4` | `36293d8bcbe485461018ed92c646b95a7238cbcce7a8ddfcfb9c06638bf16efa` | 254.0 MB |
| `thewhisper-large-v3-turbo` | `TheStageAI/thewhisper-large-v3-turbo` | `v1.4` | `25122345c95566e1053d2a1d5e07d51543274bd2873fb955f03feb2c0f2df7ad` | 569.0 MB |
| `qwen3-asr-0.6b` | `TheStageAI/Qwen3-ASR-0.6B` | `v1.4` | `af863212a49653bd04d65983245f5d7b0b70a9860f46b7d8007c7d1ec91eb26c` | 505.1 MB |
| `parakeet-tdt-0.6b-v3` | `TheStageAI/parakeet-tdt-0.6b-v3` | `v1.4` | `2a1064b8b99eeab173847e40e757c00e6fcc1914f2ed56eea81397218cfb9d20` | 250.0 MB |
| `neutts-nano-multilingual` | `TheStageAI/neutts-nano-multilingual` | `v1.4` | `f7a0f92f3617715915f62f28e8fc754585f2d4a8921e4245034a0046a5db486c` | 248.1 MB |
| `qwen3-tts-12hz-0.6b-base` | `TheStageAI/Qwen3-TTS-12Hz-0.6B-Base` | `v1.4` | `0351b57d097ba76fd67948422cc97df4a299ec138b9a3e1290d050a5fd7ca8a6` | 633.5 MB |
| `silero-vad` | `TheStageAI/silero-vad` | `v1.4` | `71bb26577c55b4a697e4513d95d9995468df22d3f68fcdbd5e2c26f59cf8ed8e` | 0.7 MB |
| `smart-turn-v3` | `TheStageAI/smart-turn-v3` | `v1.4` | `2b457ffbf1996313bc4969a0d3f256dbaca978556df286ef11fefdb37f23766a` | 8.9 MB |
| `redimnet2` | `TheStageAI/redimnet2` | `v1.4` | `1dde738b10643ce6fc6c8ca1921067a59f575134fd0259070482a39b047e17b5` | 3.7 MB |
| `speaker-segmentation` | `TheStageAI/speaker-segmentation` | `v1.4` | `9149e420fe489220b65bf1c11e541e15b698b17c8f4939bb0ebce127a50c32f7` | 3.0 MB |
| `lfm2.5-vl-450m` | `TheStageAI/LFM2.5-VL-450M` | `v1.2` | `49f7aadd733e8cf8101889ece77b11bfb9465dbb9a8c0a4e1e2dc1ed713920fe` | 273.2 MB |

## Verify

```bash
shasum -a 256 TheStageCore.xcframework/ios-arm64/TheStageCore.framework/TheStageCore
```
