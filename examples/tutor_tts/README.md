# tutor_tts

Mixed-language streaming TTS demo (iPhone). Pick a stock tagged phrase and
stream it on-device with **Qwen3-TTS**, calling `set_voice` between language
spans (`<en>…</en><es>…</es>` …).

| | |
| --- | --- |
| Platform | Physical iPhone, **iOS 18+** (Simulator not supported) |
| SDK | AppleSDK tag `__THESTAGE_SDK_VERSION__` (`TheStageSDK` → xcframework) |
| Model | HF `TheStageAI/Qwen3-TTS-12Hz-0.6B-Base` (downloaded on first **Load model**) |
| Voices | **Bundled** in this example: `VoicePacks/tutor_{en,es,fr,de,pt}/voice.json` |

Nothing else to download for voices — the five tutor packs ship in the repo
and are copied into the app bundle. The same packs are also on HF:
[Qwen3-TTS-Tutor-VoicePacks](https://huggingface.co/TheStageAI/Qwen3-TTS-Tutor-VoicePacks).

## What it exercises

- Qwen3-TTS `infer_stream` with per-span `set_voice`
- Language-tagged scripts (`LangParser` → ordered spans)
- Clone voice packs shipped next to the app (`VoicePacks/`)
- SDK `AudioStreamPlayer` for gapless PCM (same player as `macos_swift_tts`)

**Voice packs vs phrases:** `VoicePacks/tutor_*/voice.json` is clone identity
only (`ref_text` / codes / embedding). Demo lines you hear are in
`Sources/Phrases.swift`, not in the pack transcripts.

## Setup (first run)

### 1. API token

1. Sign in at [app.thestage.ai](https://app.thestage.ai/sign-in)
2. Open **Profile → API tokens** and create a token
3. Copy it (starts with something like `th_…`)

### 2. Secrets

```bash
# from the AppleSDK repo root
./scripts/setup.sh    # one-time, if needed

cd examples/tutor_tts
cp Secrets.xcconfig.example Secrets.xcconfig
```

Edit `Secrets.xcconfig` and set:

```
TS_API_TOKEN = th_your_token_here
```

(`Secrets.xcconfig` is gitignored — do not commit it.)

### 3. Generate the Xcode project

```bash
brew install xcodegen   # if needed
xcodegen generate
open TutorTTS.xcodeproj
```

### 4. Signing in Xcode

1. Select the **TutorTTS** target → **Signing & Capabilities**
2. Enable **Automatically manage signing**
3. Choose your **Team** (Apple Developer team)
4. If needed, change the **Bundle Identifier** from the placeholder
   `com.example.tutortts` to something unique under your account
   (e.g. `com.yourcompany.tutortts`)

### 5. Run on a device

1. Plug in a physical iPhone (iOS 18+), unlock it, trust the computer if asked
2. In Xcode, pick that device as the run destination
3. Prefer **Release** (Product → Scheme → Edit Scheme → Run → Build Configuration → Release)
4. Press **Run**

On the phone, if the app won’t open: **Settings → General → VPN & Device Management** → trust your developer certificate.

### Optional: CLI install

```bash
./build_and_run.sh
# DEVICE_ID=<udid> ./build_and_run.sh
```

## App flow

1. **Load model** — downloads / compiles Qwen3-TTS on first launch (needs network + token)
2. Select a stock phrase (or edit the tagged script)
3. **Play stream** — each span: `set_voice` → `infer_stream` → speaker

## Make your own voice packs

Public codec helpers (no private TheStage Models tooling):

`examples/tools/prepare_voice_packs/` — see that folder’s README
(`prepare_qwen3_voice_pack.py` / `prepare_neutts_voice_pack.py`).

## Notes

- This example pins the published `TheStageSDK` SwiftPM product from the
  AppleSDK checkout (`Package.swift` at the repo root).
- Mic is not used — output-only TTS.
