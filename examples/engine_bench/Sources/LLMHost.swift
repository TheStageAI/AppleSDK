import Foundation
import TheStageSDK

// --------------------------------------------------------------------------------------
// LLMHost
// --------------------------------------------------------------------------------------
// Thin wrapper around the SDK: one-time `TheStageAI.initialize` (token from the
// gitignored Secrets.xcconfig -> Info.plist `TSAPIToken`) plus a one-slot
// `TheStageLLM` cache. Only the currently selected model stays resident — three
// CoreML decoders at once would be hundreds of MB of compiled ANE state — so
// switching models releases the previous one before loading the next.

enum LLMHostError: LocalizedError {
    case missingToken

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "TSAPIToken missing. Set TS_API_TOKEN in Secrets.xcconfig."
        }
    }
}

@MainActor
final class LLMHost {
    static let shared = LLMHost()
    private init() {}

    private var initialized = false
    private var current: (name: String, llm: TheStageLLM)?

    /// Validate the API token exactly once per process (online required;
    /// offline initialize fails inside the SDK).
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

    /// Load (or return the cached) decoder for `model`, releasing any other
    /// resident model first. Bundled models load from the app bundle; anything
    /// else is fetched from the model's HF repo (download -> extract ->
    /// decrypt, cached by the SDK) with `onProgress` reporting the phases.
    func llm(
        for model: BundledModel,
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
