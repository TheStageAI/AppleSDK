import Foundation

// --------------------------------------------------------------------------------------
// LangSegment / LangTagParser — split `<xx>…</xx>` tutor scripts into TTS spans
// --------------------------------------------------------------------------------------
/// One language span after parsing a tagged script.
struct LangSegment: Equatable, Identifiable {
    var id: String { "\(tag)-\(text)" }
    /// Short tag from markup (`en`, `es`, …) → `VoicePacks/tutor_<tag>`.
    let tag: String
    /// Qwen3-TTS `language=` string (`english`, `spanish`, …).
    let qwen_language: String
    /// Plain text spoken for this span (not the clone ref_text).
    let text: String
}

enum LangTagParser {

    // ----------------------------------------------------------------------------------
    // Public Attributes
    // ----------------------------------------------------------------------------------
    static let tag_to_qwen: [String: String] = [
        "en": "english",
        "es": "spanish",
        "fr": "french",
        "de": "german",
        "zh": "chinese",
        "ja": "japanese",
        "ko": "korean",
        "pt": "portuguese",
    ]

    // ----------------------------------------------------------------------------------
    // Public Methods
    // ----------------------------------------------------------------------------------
    /// Parse nested-safe paired tags. Untagged glue uses ``default_tag``.
    static func parse(
        _ input: String, default_tag: String = "en"
    ) throws -> [LangSegment] {
        guard tag_to_qwen[default_tag.lowercased()] != nil else {
            throw ParseError.unknownTag(default_tag)
        }
        let pattern = #"<([a-zA-Z]{2})\b[^>]*>([\s\S]*?)</\1>"#
        let re = try NSRegularExpression(pattern: pattern)
        let ns = input as NSString
        let full = NSRange(location: 0, length: ns.length)
        var segments: [LangSegment] = []
        var cursor = 0

        for match in re.matches(in: input, range: full) {
            if match.range.location > cursor {
                let before = ns.substring(
                    with: NSRange(
                        location: cursor,
                        length: match.range.location - cursor
                    )
                )
                try __append_untagged(
                    before, default_tag: default_tag, into: &segments
                )
            }
            let tag = ns.substring(with: match.range(at: 1)).lowercased()
            let body = ns.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                segments.append(
                    LangSegment(
                        tag: tag,
                        qwen_language: try __qwen(for: tag),
                        text: body
                    )
                )
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            try __append_untagged(
                ns.substring(from: cursor),
                default_tag: default_tag,
                into: &segments
            )
        }
        guard !segments.isEmpty else { throw ParseError.empty }
        return segments
    }

    // ----------------------------------------------------------------------------------
    // Private Methods
    // ----------------------------------------------------------------------------------
    private static func __append_untagged(
        _ raw: String,
        default_tag: String,
        into segments: inout [LangSegment]
    ) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let tag = default_tag.lowercased()
        segments.append(
            LangSegment(
                tag: tag,
                qwen_language: try __qwen(for: tag),
                text: trimmed
            )
        )
    }

    private static func __qwen(for tag: String) throws -> String {
        guard let name = tag_to_qwen[tag.lowercased()] else {
            throw ParseError.unknownTag(tag)
        }
        return name
    }

    enum ParseError: LocalizedError {
        case unknownTag(String)
        case empty

        var errorDescription: String? {
            switch self {
            case .unknownTag(let t): return "unknown tag <\(t)>"
            case .empty: return "no speakable segments"
            }
        }
    }
}
