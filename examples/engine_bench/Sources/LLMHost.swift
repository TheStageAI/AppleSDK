import Foundation
import TheStageSDK

// --------------------------------------------------------------------------------------
// LLMHost
// --------------------------------------------------------------------------------------
// Thin wrapper around the SDK: one-time `TheStageAI.initialize` (token from the
// gitignored Secrets.xcconfig -> Info.plist `TSAPIToken`) plus a one-slot
// text-model cache. Only the currently selected model stays resident — three
// CoreML decoders at once would be hundreds of MB of compiled ANE state — so
// switching models releases the previous one before loading the next.
//
// `thestage_llm` packs open as `TSLLM`; a `thestage_vl` pack (Gemma-4 E2B, a
// gemma-vl root with no encoder leaf yet) opens as `TSVLM` and is driven
// through the same text-only calls, so the tab benchmarks both alike.

/// The text-generation surface this tab needs from either pipeline.
protocol BenchTextModel: AnyObject {
    var generation_defaults: LLMGenerationConfig { get }
    func infer(prompt: String, config: LLMGenerationConfig) throws -> LLMResult
    func infer_stream(
        prompt: String, config: LLMGenerationConfig
    ) throws -> AsyncStream<LLMStreamChunk>
    func release()
    /// Per-node graph timings when `QLIP_GRAPH_PROFILE` is set; nil otherwise.
    func profile_report() -> String?
    /// Generate from pre-templated token ids (dataset benches).
    func infer(prompt_ids: [Int], config: LLMGenerationConfig) throws -> LLMResult
    /// Tokens per verify cycle of the last speculative request; nil on plain.
    var spec_tokens_per_cycle: Double? { get }
}

extension TSLLM: BenchTextModel {
    func infer(prompt: String, config: LLMGenerationConfig) throws -> LLMResult {
        infer(prompt: prompt, system_prompt: nil, config: config)
    }

    func infer(prompt_ids: [Int], config: LLMGenerationConfig) throws -> LLMResult {
        infer(prompt_token_ids: prompt_ids, config: config)
    }

    var spec_tokens_per_cycle: Double? { last_spec_acceptance_length }

    func infer_stream(
        prompt: String, config: LLMGenerationConfig
    ) throws -> AsyncStream<LLMStreamChunk> {
        infer_stream(prompt: prompt, system_prompt: nil, config: config)
    }
}

extension TSVLM: BenchTextModel {
    func infer(prompt: String, config: LLMGenerationConfig) throws -> LLMResult {
        try infer(prompt: prompt, system_prompt: nil, config: config)
    }

    func infer_stream(
        prompt: String, config: LLMGenerationConfig
    ) throws -> AsyncStream<LLMStreamChunk> {
        try infer_stream(prompt: prompt, system_prompt: nil, config: config)
    }

    func profile_report() -> String? { nil }

    func infer(prompt_ids: [Int], config: LLMGenerationConfig) throws -> LLMResult {
        throw LLMHostError.tokenPromptsUnsupported
    }

    var spec_tokens_per_cycle: Double? { nil }
}

enum LLMHostError: LocalizedError {
    case missingToken
    case tokenPromptsUnsupported

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "TSAPIToken missing. Set TS_API_TOKEN in Secrets.xcconfig."
        case .tokenPromptsUnsupported:
            return "This model opens as a VLM; token-id prompt sets need an LLM entry."
        }
    }
}

@MainActor
final class LLMHost {
    static let shared = LLMHost()
    private init() {}

    private var initialized = false
    private var current: (name: String, llm: any BenchTextModel)?

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
        try await TheStageAI.shared.initialize(api_token: token)
        initialized = true
    }

    /// Load (or return the cached) decoder for `model`, releasing any other
    /// resident model first. Bundled models load from the app bundle; anything
    /// else is fetched from the model's HF repo (download -> extract ->
    /// decrypt, cached by the SDK) with `onProgress` reporting the phases.
    func llm(
        for model: BundledModel,
        onProgress: LoadProgressHandler? = nil
    ) async throws -> any BenchTextModel {
        try await ensureInitialized()
        if let current, current.name == model.name {
            return current.llm
        }
        if let current {
            current.llm.release()
        }
        current = nil
        let llm: any BenchTextModel
        switch model.family {
        case .llm:
            llm = try await TSLLM(
                engines_path: model.enginesPath(),
                device: "npu",
                chat_template: model.template,
                revision: model.revision,
                on_load_progress: onProgress
            )
        case .vl:
            // Chat template comes from the pack's tokenizer leaf.
            llm = try await TSVLM(
                engines_path: model.enginesPath(),
                device: "npu",
                revision: model.revision,
                on_load_progress: onProgress
            )
        }
        current = (model.name, llm)
        return llm
    }
}
