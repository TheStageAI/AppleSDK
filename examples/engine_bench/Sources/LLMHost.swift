import Foundation
import TheStageSDK

// LLMHost — initialize once, keep a single resident TheStageLLM.

enum LLMHostError: LocalizedError {
    case missingToken

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "TSAPIToken missing. Copy Secrets.xcconfig.example → Secrets.xcconfig and set TS_API_TOKEN."
        }
    }
}

@MainActor
final class LLMHost {
    static let shared = LLMHost()
    private init() {}

    private var initialized = false
    private var current: (name: String, llm: TheStageLLM)?

    /// Validate the API token once per process (online `initialize` required).
    func ensureInitialized() async throws {
        if initialized { return }
        guard
            let token = Bundle.main.object(
                forInfoDictionaryKey: "TSAPIToken"
            ) as? String,
            !token.isEmpty,
            token != "$(TS_API_TOKEN)"
        else {
            throw LLMHostError.missingToken
        }
        try await TheStageAI.shared.initialize(apiToken: token)
        initialized = true
    }

    /// Load (or return cached) decoder for `model`. Downloads from Hugging
    /// Face on first use; later launches hit the on-device cache.
    func llm(
        for model: CatalogModel,
        onProgress: LoadProgressHandler? = nil
    ) async throws -> TheStageLLM {
        try await ensureInitialized()
        if let current, current.name == model.name {
            return current.llm
        }
        if let current {
            current.llm.release()
        }
        current = nil
        let llm = try await TheStageLLM(
            engines_path: model.enginesPath(),
            device: "npu",
            chat_template: model.template,
            revision: model.revision,
            on_load_progress: onProgress
        )
        current = (model.name, llm)
        return llm
    }
}
