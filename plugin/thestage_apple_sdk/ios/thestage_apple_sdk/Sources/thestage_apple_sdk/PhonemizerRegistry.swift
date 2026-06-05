import Foundation
import TheStageCore

// --------------------------------------------------------------------------------------
// PhonemizerRegistry
// --------------------------------------------------------------------------------------
/// App-side injection point for a `Phonemizer` used by phoneme-based TTS
/// models (`neutts` / `neutts-nano`). The plugin itself does not depend on
/// any specific phonemizer backend (e.g. espeak-ng), so apps that need one
/// provide it in their own native target and register it here.
///
/// Register once, early (e.g. in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`),
/// before loading a nano model:
///
///   import thestage_apple_sdk
///   PhonemizerRegistry.register { language in
///       EspeakPhonemizer(language: language)
///   }
///
/// If no factory is registered when a nano model loads, the SDK falls back to
/// its built-in CoreML phonemizer (lower quality). Multilingual models never
/// consult the registry.
///
/// See extras/espeak/README.md for a ready-to-drop-in espeak implementation.
public enum PhonemizerRegistry {
    private static let __lock = NSLock()
    nonisolated(unsafe) private static var __factory:
        (@Sendable (_ language: String) -> Phonemizer)?

    /// Register a factory that builds a `Phonemizer` for a given language.
    /// The most recent registration wins. Pass `nil` to clear.
    public static func register(
        _ factory: (@Sendable (_ language: String) -> Phonemizer)?
    ) {
        __lock.lock()
        defer { __lock.unlock() }
        __factory = factory
    }

    /// Whether an app has registered a phonemizer factory.
    public static var isRegistered: Bool {
        __lock.lock()
        defer { __lock.unlock() }
        return __factory != nil
    }

    /// Build a phonemizer for `language` using the registered factory, or
    /// `nil` if none is registered.
    static func make(language: String) -> Phonemizer? {
        let factory = __lock.withLock { __factory }
        return factory?(language)
    }
}
