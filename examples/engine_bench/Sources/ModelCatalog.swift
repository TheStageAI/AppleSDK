import Foundation
import TheStageSDK

/// One LLM in the picker. Engines load from Hugging Face via the SDK
/// (`TheStageAI/<repo>` + ``ModelRevisionMap``). Optional local
/// `BundledModels/<name>/` is only for advanced offline demos — this
/// public example is HF-first and does not ship model weights.
struct CatalogModel: Identifiable, Hashable {
    let name: String
    let displayName: String
    let template: ChatTemplate
    let hfRepo: String
    /// Optional revision override. `nil` → SDK ``ModelRevisionMap``.
    let revision: String?

    var id: String { name }

    func enginesPath() -> String {
        if let dir = bundledDir() { return dir.path }
        return hfRepo
    }

    private func bundledDir() -> URL? {
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
    static let all: [CatalogModel] = [
        CatalogModel(
            name: "lfm2.5-230m",
            displayName: "LFM2.5 230M",
            template: .lfm2,
            hfRepo: "TheStageAI/LFM2.5-230M",
            revision: nil
        ),
        CatalogModel(
            name: "lfm2.5-350m",
            displayName: "LFM2.5 350M",
            template: .lfm2,
            hfRepo: "TheStageAI/LFM2.5-350M",
            revision: nil
        ),
        CatalogModel(
            name: "qwen3-0.6b",
            displayName: "Qwen3 0.6B",
            template: .qwen2,
            hfRepo: "TheStageAI/Qwen3-0.6B",
            revision: nil
        ),
        CatalogModel(
            name: "gemma3-1b-it",
            displayName: "Gemma3 1B",
            template: .gemma3,
            hfRepo: "TheStageAI/gemma-3-1b-it",
            revision: nil
        ),
    ]

    static var first: CatalogModel { all[0] }
}
