# espeak phonemizer add-on (opt-in)

The `thestage_apple_sdk` plugin does **not** depend on espeak-ng. Most apps
don't need it:

- **Multilingual** TTS (`neutts-multilingual`) and the voice agent phonemize
  internally and require no phonemizer from the app.
- **English nano** TTS (`neutts` / `neutts-nano`) needs a grapheme-to-phoneme
  step. If you don't provide one, the SDK falls back to its built-in CoreML
  phonemizer (`QlipPhonemizer`), which works but is lower quality.

For best nano quality, register the espeak-ng phonemizer shipped here. Because
espeak-ng is a native C library, it lives in **your app's** Runner target, not
in the plugin — so only nano apps pay the build/link cost.

## What's in this folder

- `EspeakPhonemizer.swift` — a `Phonemizer` implementation backed by espeak-ng
  (plus `FrenchEspeakPhonemizer`).

The espeak-ng SwiftPM package itself is **not** vendored here — it needs two
small build patches, so it's fetched and patched on demand by the setup script.

## Integration (iOS app)

1. Fetch espeak-ng and add it to your app's **Runner** target.

   From the repo root, fetch and patch the package (one time):

   ```bash
   ./scripts/setup.sh --espeak
   ```

   This clones the upstream `espeak-ng-spm` and applies the required patches
   into `extras/espeak/espeak-ng-spm`. Then in Xcode:
   `File > Add Package Dependencies… > Add Local…` and select that folder
   (copy it into your app repo if you prefer, e.g. `ios/third_party/`). Add
   both products to the Runner target:
   - `libespeak-ng`
   - `espeak-ng-data`

2. Add `EspeakPhonemizer.swift` to the Runner target (drag it into the
   `Runner` group in Xcode, or place it under `ios/Runner/`).

3. Register the phonemizer once at launch, before loading a nano model. In
   `ios/Runner/AppDelegate.swift`:

   ```swift
   import Flutter
   import UIKit
   import thestage_apple_sdk

   @main
   @objc class AppDelegate: FlutterAppDelegate {
       override func application(
           _ application: UIApplication,
           didFinishLaunchingWithOptions launchOptions:
               [UIApplication.LaunchOptionsKey: Any]?
       ) -> Bool {
           PhonemizerRegistry.register { language in
               EspeakPhonemizer(language: language)
           }
           GeneratedPluginRegistrant.register(with: self)
           return super.application(
               application, didFinishLaunchingWithOptions: launchOptions
           )
       }
   }
   ```

That's it. When you start a `neutts` / `neutts-nano` model, the plugin asks
`PhonemizerRegistry` for a phonemizer and uses your espeak implementation. If
you skip registration, nano still runs via the CoreML fallback.

## Notes

- The espeak-ng data bundle is installed once on first use into the app's
  Application Support directory (see `EspeakLib.ensureBundleInstalled`).
- The `Phonemizer` protocol comes from `TheStageCore`. `EspeakPhonemizer.swift`
  already `import`s it, so the `AppDelegate` snippet above only needs
  `import thestage_apple_sdk`. If you reference `Phonemizer` directly elsewhere,
  add `import TheStageCore`.
- macOS apps follow the same pattern; register in
  `applicationDidFinishLaunching` instead.
