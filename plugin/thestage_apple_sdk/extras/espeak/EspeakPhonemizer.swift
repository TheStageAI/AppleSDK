import Foundation
import TheStageCore
import libespeak_ng
import os


// --------------------------------------------------------------------------------------
// EspeakPhonemizer
// --------------------------------------------------------------------------------------
/// Phonemizer backed by the espeak-ng C library.
///
/// Mirrors the behaviour of ``neutts.phonemizers.BasePhonemizer``
/// from the Python reference:
///   - ``preprocess(_:)`` — language-specific text preprocessing.
///   - ``clean(_:)`` — language-specific phoneme cleanup.
///   - ``phonemize(_:)`` — full pipeline: preprocess → espeak → clean.
///
/// espeak-ng data is compiled from the SPM resource bundle on the
/// first call to ``init`` (one-time, persists across app launches).
///
/// This file is an OPT-IN add-on for apps that load a neutts-nano model.
/// It is NOT compiled into the thestage_apple_sdk plugin (which no longer
/// depends on espeak-ng). To use it, drop this file into your app's native
/// iOS Runner target, add the espeak-ng SwiftPM package to that target, and
/// register the phonemizer with the plugin before starting a nano model:
///
///   import thestage_apple_sdk
///   PhonemizerRegistry.register { language in
///       EspeakPhonemizer(language: language)
///   }
///
/// See extras/espeak/README.md for the full integration guide.
public class EspeakPhonemizer: Phonemizer, @unchecked Sendable {
    // Private Attributes
    // ----------------------------------------------------------------------------------
    private static let __logger = Logger(
        subsystem: "thestage_apple_sdk", category: "EspeakPhonemizer"
    )
    private static var __initialized = false
    private static let __lock = NSLock()

    private let __language: String

    // Constructor
    // ----------------------------------------------------------------------------------
    public init(language: String = "en-us") {
        __language = language
        Self.__ensure_initialized(language: language)
    }

    deinit {}

    // Public Methods
    // ----------------------------------------------------------------------------------

    /// Convert text to IPA phonemes via espeak-ng.
    ///
    /// Punctuation is preserved in its original position, matching
    /// the Python ``phonemizer`` library's ``preserve_punctuation=True``.
    public func phonemize(_ text: String) -> String {
        let preprocessed = preprocess(text)
        let raw = __phonemize_preserve_punct(preprocessed)
        return clean(raw)
    }

    /// Language-specific text preprocessing hook.
    /// Override in subclasses for custom behaviour.
    public func preprocess(_ text: String) -> String {
        return text
    }

    /// Language-specific phoneme cleanup hook.
    /// Override in subclasses for custom behaviour.
    public func clean(_ phonemes: String) -> String {
        return phonemes
    }

    // Private Methods — Initialization
    // ----------------------------------------------------------------------------------
    private static func __ensure_initialized(
        language: String
    ) {
        __lock.lock()
        defer { __lock.unlock() }

        if __initialized { return }

        let fm = FileManager.default
        let appSupport = fm.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let espeakRoot = appSupport.appendingPathComponent(
            "espeak-ng"
        )

        do {
            try fm.createDirectory(
                at: espeakRoot,
                withIntermediateDirectories: true
            )

            try EspeakLib.ensureBundleInstalled(
                inRoot: espeakRoot
            )
        } catch {
            __logger.error(
                "Failed to install espeak-ng data: \(error.localizedDescription)"
            )
            return
        }

        let status = espeakRoot.path.withCString { cStr in
            espeak_Initialize(
                AUDIO_OUTPUT_SYNCHRONOUS, 0, cStr, 0
            )
        }

        guard status > 0 else {
            __logger.error(
                "espeak_Initialize failed with status \(status)"
            )
            return
        }

        language.withCString { cStr in
            espeak_SetVoiceByName(cStr)
        }

        __initialized = true
        __logger.info("espeak-ng initialized for '\(language)'")
    }

    // Private Methods — Phonemization
    // ----------------------------------------------------------------------------------

    private static let __punctuation: Set<Character> = Set(
        ";:,.!?¡¿—…\"«»\u{201C}\u{201D}"
    )

    /// Phonemize with punctuation preservation, matching Python
    /// ``phonemizer`` library's ``preserve_punctuation=True``:
    ///   1. Split text into alternating (text, punct) segments
    ///   2. Phonemize only text segments via espeak
    ///   3. Reassemble with punctuation in its original position
    private func __phonemize_preserve_punct(
        _ text: String
    ) -> String {
        var segments: [(content: String, isPunct: Bool)] = []
        var current = ""
        var inPunct = false

        for ch in text {
            let charIsPunct = Self.__punctuation.contains(ch)
            if charIsPunct != inPunct && !current.isEmpty {
                segments.append((current, inPunct))
                current = ""
            }
            inPunct = charIsPunct
            current.append(ch)
        }
        if !current.isEmpty {
            segments.append((current, inPunct))
        }

        var parts: [String] = []
        for (content, isPunct) in segments {
            if isPunct {
                parts.append(content)
            } else {
                let trimmed = content.trimmingCharacters(
                    in: .whitespaces
                )
                guard !trimmed.isEmpty else { continue }
                let ph = __phonemize_raw(trimmed)
                guard !ph.isEmpty else { continue }
                let hasLeadingSpace =
                    content.first?.isWhitespace == true
                if hasLeadingSpace && !parts.isEmpty {
                    parts.append(" " + ph)
                } else {
                    parts.append(ph)
                }
            }
        }

        return parts.joined()
    }

    /// Raw ``espeak_TextToPhonemes`` call.
    /// Flag 0x02 = IPA output with stress markers.
    private func __phonemize_raw(_ text: String) -> String {
        var parts: [String] = []
        text.withCString { cStr in
            var ptr: UnsafeRawPointer? =
                UnsafeRawPointer(cStr)
            while let current = ptr {
                let byte = current.load(as: UInt8.self)
                guard byte != 0 else { break }

                guard
                    let phonemes =
                        espeak_TextToPhonemes(
                            &ptr, 0, 0x02
                        )
                else { break }

                let chunk = String(cString: phonemes)
                let trimmed = chunk.trimmingCharacters(
                    in: .whitespaces
                )
                if !trimmed.isEmpty {
                    parts.append(trimmed)
                }
            }
        }
        return parts.joined(separator: " ")
    }
}


// --------------------------------------------------------------------------------------
// FrenchEspeakPhonemizer
// --------------------------------------------------------------------------------------
/// French-specific phonemizer matching
/// ``neutts.phonemizers.FrenchPhonemizer``.
public final class FrenchEspeakPhonemizer: EspeakPhonemizer {
    public init() {
        super.init(language: "fr-fr")
    }

    override public func clean(_ phonemes: String) -> String {
        return phonemes.replacingOccurrences(of: "-", with: "")
    }
}
