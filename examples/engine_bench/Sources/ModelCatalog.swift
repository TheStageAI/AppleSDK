import Foundation
import TheStageSDK

/// Which SDK pipeline opens the pack. `thestage_llm` packs open through
/// ``TSLLM``; a `thestage_vl` pack opens through ``TSVLM`` and is driven
/// text-only here (Gemma-4 E2B ships as a gemma-vl root with no encoder
/// leaf yet, so it is a chat LLM on this tab).
enum BundledFamily: Hashable {
    case llm
    case vl
}

/// One LLM in the picker. Engines load from Hugging Face via the SDK
/// (`TheStageAI/<repo>` + ``ModelRevisionMap``). Optional local
/// `BundledModels/<name>/` is only for advanced offline demos — this
/// public example is HF-first and does not ship model weights.
struct BundledModel: Identifiable, Hashable {
    let name: String
    let displayName: String
    let template: ChatTemplate
    let hfRepo: String
    /// Optional revision override. `nil` → SDK ``ModelRevisionMap``.
    let revision: String?
    var family: BundledFamily = .llm
    /// Ships a root-slot proposer regardless of revision (a local dev pack).
    var speculative: Bool = false
    /// Listed only when `BundledModels/<name>/` is in the app bundle.
    var localOnly: Bool = false

    var id: String { name }

    /// Tokenizer family of the offline prompt sets this model can run
    /// (`BundledModels/_datasets/<family>/`); `nil` = none. The ids are
    /// pre-templated, so a set only fits the tokenizer it was built with,
    /// and only `TSLLM` takes token ids.
    var promptFamily: String? {
        guard family == .llm else { return nil }
        switch template {
        case .gemma4: return "gemma4"
        case .lfm2: return "lfm2.5"
        default: return nil
        }
    }

    /// Packs published on the speculative-decoding revision ship a proposer;
    /// the toggle then drives `LLMGenerationConfig.speculative_decoding`.
    var supportsSpeculation: Bool {
        speculative || revision == ModelCatalog.speculativeRevision
    }

    func enginesPath() -> String {
        if let dir = enginesURL() { return dir.path }
        return hfRepo
    }

    /// Path-based only: `Bundle.url(forResource:)` splits on `.`, so names
    /// like `lfm2.5-230m` / `qwen3-0.6b` mis-resolve.
    func enginesURL() -> URL? {
        let dir = Bundle.main.resourceURL?
            .appendingPathComponent("BundledModels", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        if let dir, FileManager.default.fileExists(atPath: dir.path) {
            return dir
        }
        return nil
    }
}

enum ModelCatalog {
    /// The speculative packs (root-slot drafter, bundle-bound QLPA) are the
    /// SDK 1.5 line: ``ModelRevisionMap`` pins them at `v1.5`, so entries pass
    /// no revision and declare `speculative` themselves.
    static let speculativeRevision = "v1.5"

    /// Picker order; local-only dev packs appear when they are bundled.
    static var all: [BundledModel] {
        catalog.filter { !$0.localOnly || $0.enginesURL() != nil }
    }

    private static let catalog: [BundledModel] = [
        // LFM2.5 ships from the speculative revision only: the pack carries
        // the compact drafter, and the switch runs it plain or speculative.
        BundledModel(
            name: "lfm2.5-230m-compact",
            displayName: "LFM2.5 230M",
            template: .lfm2,
            hfRepo: "TheStageAI/LFM2.5-230M",
            revision: nil,
            speculative: true
        ),
        BundledModel(
            name: "lfm2.5-350m-compact",
            displayName: "LFM2.5 350M",
            template: .lfm2,
            hfRepo: "TheStageAI/LFM2.5-350M",
            revision: nil,
            speculative: true
        ),
        BundledModel(
            name: "qwen3-0.6b",
            displayName: "Qwen3 0.6B",
            template: .qwen2,
            hfRepo: "TheStageAI/Qwen3-0.6B",
            revision: nil
        ),
        BundledModel(
            name: "gemma3-1b-it",
            displayName: "Gemma3 1B",
            template: .gemma3,
            hfRepo: "TheStageAI/gemma-3-1b-it",
            revision: nil
        ),
        // Gemma-4 E2B from the speculative revision: decoder + DFlash2 drafter
        // (selector tree + PRESTO, verify 32) + vision tower in one pack. Here
        // it opens text-only through TSLLM with the drafter (token-id prompt
        // sets, the speculative switch); the VLM tab opens the same pack with
        // its tower and always decodes plain.
        BundledModel(
            name: "gemma4-e2b-it",
            displayName: "Gemma4 E2B",
            template: .gemma4,
            hfRepo: "TheStageAI/gemma-4-E2B-it",
            revision: nil,
            family: .llm,
            speculative: true
        ),
    ]

    static var first: BundledModel { all[0] }
}
