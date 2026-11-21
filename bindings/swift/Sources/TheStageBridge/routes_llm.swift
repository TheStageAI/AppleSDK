import Foundation
import TheStageSDK


// --------------------------------------------------------------------------------------
// SDKRoutes
// --------------------------------------------------------------------------------------
/// `sdk.initialize`, `sdk.release`, `sdk.stop_model`, `sdk.delete_model`.
enum SDKRoutes {
    static func register(in core: BridgeCore) {
        core.register("sdk.initialize") { call in
            let token = try call.string("api_token")
            let hf = call.string("hf_token", default: nil)
            try await TheStageAI.shared.initialize(api_token: token, hf_token: hf)
            return .init(["initialized": true])
        }
        /// Drop a handle the client no longer needs.
        core.register("sdk.release") { call in
            call.core.release(try call.string("handle"))
            return .init()
        }
        /// Unload a model loaded under `model_name`.
        core.register("sdk.stop_model") { call in
            let name = try call.string("model_name")
            _ = try await MainActor.run {
                try TheStageAI.shared.stop_model(model_name: name)
            }
            return .init()
        }
        /// Delete a downloaded pack (`TheStageAI.delete_model`); `revision` absent
        /// deletes every revision.
        core.register("sdk.delete_model") { call in
            let path = try call.string("engines_path")
            let revision = call.string("revision", default: nil)
            let deletion = try await TheStageAI.shared.delete_model(
                engines_path: path, revision: revision)
            return .init([
                "freed_bytes": deletion.freed_bytes,
                "revisions": deletion.revisions,
            ])
        }
    }
}


// --------------------------------------------------------------------------------------
// LLMRoutes
// --------------------------------------------------------------------------------------
/// `llm.load`, `llm.infer`, `llm.infer_stream`, `llm.infer_events`, `chat.open`,
/// `chat.infer_stream`, `chat.history`, `chat.clear`, `chat.cancel`.
enum LLMRoutes {
    static func register(in core: BridgeCore) {
        /// `TheStageAI.start_model(TSLLM.self, model_name:, engines_path:, device:)`.
        core.register("llm.load") { call in
            let path = try call.string("engines_path")
            let name = call.string("model_name", default: path) ?? path
            let device = call.string("device", default: "npu") ?? "npu"
            let llm = try await TheStageAI.shared.start_model(
                TSLLM.self, model_name: name, engines_path: path, device: device)
            let handle = call.core.keep(llm, prefix: "llm")
            return .init([
                "handle": handle, "model_name": name,
                "generation_defaults": BridgeCodec.encode(llm.generation_defaults),
            ])
        }
        core.register("llm.infer") { call in
            let llm = try call.object("llm", as: TSLLM.self)
            let config = BridgeCodec.llm_config(
                call.dict("config"), base: llm.generation_defaults)
            let prompt = try call.string("prompt")
            let system = call.string("system_prompt", default: nil)
            let result = try await Task.detached {
                try llm.infer(prompt: prompt, system_prompt: system, config: config)
            }.value
            return .init([
                "text": result.text, "prompt_tokens": result.prompt_tokens,
                "generated_tokens": result.generated_tokens,
                "prefill_seconds": result.prefill_seconds,
                "decode_seconds": result.decode_seconds,
            ])
        }
        /// Tokens as they decode: `chunk` events, then `end`. The input is a
        /// `prompt`, or `messages` (a whole conversation, trimmed to the context).
        core.register("llm.infer_stream") { call in
            let llm = try call.object("llm", as: TSLLM.self)
            let config = BridgeCodec.llm_config(
                call.dict("config"), base: llm.generation_defaults)
            let system = call.string("system_prompt", default: nil)
            let chunks =
                call.params["messages"] == nil
                ? llm.infer_stream(
                    prompt: try call.string("prompt"), system_prompt: system,
                    config: config)
                : llm.infer_stream(
                    messages: try Self.__fitted(
                        call, llm: llm, tools: [], system: system, config: config),
                    system_prompt: system, config: config)
            let core = call.core
            let stream = core.keep(StreamToken(), prefix: "stream")
            return .init(
                ["stream": stream],
                after: {
                    Task {
                        for await chunk in chunks {
                            core.event(stream, "chunk", BridgeCodec.encode(chunk))
                        }
                        core.end(stream)
                        core.release(stream)
                    }
                })
        }
        /// A conversation as `LLMStreamEvent`s (`text_delta`, `thinking_delta`,
        /// `tool_call`, `final`, then `end`). With `tools`, a call the model makes
        /// comes back to the caller, who runs it and sends the result as a `tool`
        /// message (`infer_stream(messages:tools:executor: nil)`).
        core.register("llm.infer_events") { call in
            let llm = try call.object("llm", as: TSLLM.self)
            let config = BridgeCodec.llm_config(
                call.dict("config"), base: llm.generation_defaults)
            let system = call.string("system_prompt", default: nil)
            let tools = try BridgeCodec.tools(
                call.params["tools"] as? [[String: Any]] ?? [])
            let messages = try Self.__fitted(
                call, llm: llm, tools: tools, system: system, config: config)
            let events =
                tools.isEmpty
                ? Self.__events(
                    llm.infer_stream(
                        messages: messages, system_prompt: system, config: config))
                : try llm.infer_stream(
                    messages: messages, tools: tools.definitions, executor: nil,
                    system_prompt: system, config: config)
            let core = call.core
            let stream = core.keep(StreamToken(), prefix: "stream")
            return .init(
                ["stream": stream],
                after: {
                    Task {
                        for await event in events {
                            let (name, data) = BridgeCodec.encode(event)
                            core.event(stream, name, data)
                        }
                        core.end(stream)
                        core.release(stream)
                    }
                })
        }
        /// `llm.chat_session(system_prompt:, tools:, memory:)`. Tools with `callback`
        /// run in the client through the returned `tools` relay (``ToolRelay``).
        core.register("chat.open") { call in
            let llm = try call.object("llm", as: TSLLM.self)
            let turns = call.int("max_turns") ?? TSSlidingWindowMemory.product_max_turns
            let (relay, tools) = try ToolRelay.make(
                core: call.core, items: call.params["tools"] as? [[String: Any]] ?? [])
            let session = llm.chat_session(
                system_prompt: call.string("system_prompt", default: nil),
                tools: tools,
                memory: .SLIDING(max_turns: turns))
            let handle = call.core.keep(
                ChatHandle(session: session, llm: llm, relay: relay), prefix: "chat")
            var result: [String: Any] = ["handle": handle]
            if let relay { result["tools"] = relay.handle }
            return .init(result)
        }
        /// `session.infer_stream(user_request:, config:)`: `text_delta`,
        /// `thinking_delta`, `tool_call`, `tool_result`, `final`, then `end`.
        core.register("chat.infer_stream") { call in
            let chat = try call.object("chat", as: ChatHandle.self)
            let config = BridgeCodec.llm_config(
                call.dict("config"), base: chat.llm.generation_defaults)
            let events = try chat.session.infer_stream(
                user_request: try call.string("user_request"), config: config)
            let core = call.core
            let stream = core.keep(StreamToken(), prefix: "stream")
            return .init(
                ["stream": stream],
                after: {
                    Task {
                        for await event in events {
                            let (name, data) = BridgeCodec.encode(event)
                            core.event(stream, name, data)
                        }
                        core.end(stream)
                        core.release(stream)
                    }
                })
        }
        core.register("chat.history") { call in
            let chat = try call.object("chat", as: ChatHandle.self)
            return .init(["messages": chat.session.history.map(BridgeCodec.encode)])
        }
        core.register("chat.clear") { call in
            try call.object("chat", as: ChatHandle.self).session.clear()
            return .init()
        }
        core.register("chat.cancel") { call in
            try call.object("chat", as: ChatHandle.self).session.cancel_in_flight()
            return .init()
        }
    }
}


extension LLMRoutes {

    // Private Methods
    // ----------------------------------------------------------------------------------
    /// The call's `messages`, oldest user-led turns dropped until the prompt and
    /// an answer fit the model's context (what a chat session does with memory).
    private static func __fitted(
        _ call: BridgeCall, llm: TSLLM, tools: [Tool], system: String?,
        config: LLMGenerationConfig
    ) throws -> [ChatTemplate.Message] {
        guard let items = call.params["messages"] as? [[String: Any]] else {
            throw BridgeError.missing_param("messages")
        }
        return LLMChatEngine(llm: llm)
            .fit_messages(
                try BridgeCodec.chat_messages(items), system_prompt: system, tools: tools,
                config: config
            )
            .map { $0.to_template_message() }
    }

    /// Chunks as events: each piece of text a `text_delta`, the last chunk `final`.
    private static func __events(
        _ chunks: AsyncStream<LLMStreamChunk>
    ) -> AsyncStream<LLMStreamEvent> {
        AsyncStream { continuation in
            Task {
                var raw = ""
                for await chunk in chunks {
                    if !chunk.text.isEmpty {
                        raw += chunk.text
                        continuation.yield(.text_delta(chunk.text))
                    }
                    if chunk.is_final {
                        continuation.yield(
                            .final(
                                stop_reason: chunk.stop_reason,
                                prompt_tokens: chunk.prompt_tokens,
                                generated_tokens: chunk.generated_tokens,
                                tokens_per_second: chunk.tokens_per_second,
                                total_seconds: chunk.total_seconds, raw_text: raw,
                                metrics: nil))
                    }
                }
                continuation.finish()
            }
        }
    }
}


// --------------------------------------------------------------------------------------
// Handles
// --------------------------------------------------------------------------------------
/// A chat session, the model it decodes with (for its defaults) and the relay of its
/// client-run tools, closed with the session.
final class ChatHandle: @unchecked Sendable {

    // Public Attributes
    // ----------------------------------------------------------------------------------
    let session: TSChatSession
    let llm: TSLLM
    let relay: ToolRelay?

    // Constructor
    // ----------------------------------------------------------------------------------
    init(session: TSChatSession, llm: TSLLM, relay: ToolRelay? = nil) {
        self.session = session
        self.llm = llm
        self.relay = relay
    }

    deinit { relay?.close() }
}

/// A placeholder that reserves a stream's handle while it pumps.
final class StreamToken: @unchecked Sendable {
    deinit {}
}
