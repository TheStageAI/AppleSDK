import Foundation

// --------------------------------------------------------------------------------------
// PromptSets — offline, pre-templated prompt sets for dataset benchmarks
// --------------------------------------------------------------------------------------
/// One prompt of a set: already chat-templated token ids, so a benchmark
/// measures the model on exactly the tokens the reference eval used.
struct PromptRow: Decodable, Hashable {
    let src: String
    let id: String
    let prompt_ids: [Int]
}

/// A prompt set for one tokenizer family (`BundledModels/_datasets/<family>/
/// <name>.jsonl`, one `{src, id, prompt_ids}` row per line). Nothing ships in
/// the public example; a dev build drops the files in next to its packs.
struct PromptSet: Identifiable, Hashable {
    let family: String
    let name: String
    let rows: [PromptRow]

    var id: String { "\(family)/\(name)" }
    /// Sources in first-seen order (the picker's filter entries).
    var sources: [String] {
        var seen: [String] = []
        for r in rows where !seen.contains(r.src) { seen.append(r.src) }
        return seen
    }

    func rows(source: String?) -> [PromptRow] {
        guard let source else { return rows }
        return rows.filter { $0.src == source }
    }
}

enum PromptSetCatalog {
    private static let root = Bundle.main.resourceURL?
        .appendingPathComponent("BundledModels/_datasets", isDirectory: true)

    /// Sets for a tokenizer family, sorted by name; empty when none shipped.
    static func sets(family: String?) -> [PromptSet] {
        guard let family, let root else { return [] }
        let dir = root.appendingPathComponent(family, isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let rows = text.split(separator: "\n").compactMap {
                    try? JSONDecoder().decode(PromptRow.self, from: Data($0.utf8))
                }
                guard !rows.isEmpty else { return nil }
                return PromptSet(
                    family: family, name: url.deletingPathExtension().lastPathComponent,
                    rows: rows)
            }
    }
}
