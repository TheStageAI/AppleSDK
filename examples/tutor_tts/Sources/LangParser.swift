import Foundation

struct LangSegment: Equatable, Identifiable {
    var id: String { "\(tag)-\(text)" }
    let tag: String
    let qwen_language: String
    let text: String
}

enum LangTagParser {
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

        func append_untagged(_ raw: String) throws {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let tag = default_tag.lowercased()
            segments.append(LangSegment(
                tag: tag,
                qwen_language: try qwen(for: tag),
                text: trimmed
            ))
        }

        for match in re.matches(in: input, range: full) {
            if match.range.location > cursor {
                let before = ns.substring(
                    with: NSRange(
                        location: cursor,
                        length: match.range.location - cursor
                    )
                )
                try append_untagged(before)
            }
            let tag = ns.substring(with: match.range(at: 1)).lowercased()
            let body = ns.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                segments.append(LangSegment(
                    tag: tag,
                    qwen_language: try qwen(for: tag),
                    text: body
                ))
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            try append_untagged(ns.substring(from: cursor))
        }
        guard !segments.isEmpty else { throw ParseError.empty }
        return segments
    }

    private static func qwen(for tag: String) throws -> String {
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
