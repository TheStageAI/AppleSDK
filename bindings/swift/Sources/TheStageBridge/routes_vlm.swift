import CoreGraphics
import Foundation
import TheStageSDK


// --------------------------------------------------------------------------------------
// VLMRoutes
// --------------------------------------------------------------------------------------
/// `vlm.load`, `vlm.infer`, `vlm.infer_stream`. Images come as encoded files
/// (JPEG, PNG, HEIC): `image_paths`, and/or the call's body holding the files
/// back to back with their byte counts in `image_lengths`.
enum VLMRoutes {
    static func register(in core: BridgeCore) {
        /// `TheStageAI.start_model(TSVLM.self, model_name:, engines_path:, device:)`.
        core.register("vlm.load") { call in
            let path = try call.string("engines_path")
            let name = call.string("model_name", default: path) ?? path
            let vlm = try await TheStageAI.shared.start_model(
                TSVLM.self, model_name: name, engines_path: path,
                device: call.string("device", default: "npu") ?? "npu")
            return .init([
                "handle": call.core.keep(vlm, prefix: "vlm"), "model_name": name,
                "generation_defaults": BridgeCodec.encode(vlm.generation_defaults),
            ])
        }
        core.register("vlm.infer") { call in
            let vlm = try call.object("vlm", as: TSVLM.self)
            let images = try Self.images(call)
            let config = BridgeCodec.llm_config(
                call.dict("config"), base: vlm.generation_defaults)
            let prompt = try call.string("prompt")
            let system = call.string("system_prompt", default: nil)
            let result = try await Task.detached {
                try vlm.infer(
                    images: images, prompt: prompt, system_prompt: system, config: config)
            }.value
            return .init([
                "text": result.text, "prompt_tokens": result.prompt_tokens,
                "generated_tokens": result.generated_tokens,
                "prefill_seconds": result.prefill_seconds,
                "decode_seconds": result.decode_seconds,
            ])
        }
        /// Tokens as they decode: `chunk` events, then `end`. The text is a
        /// `prompt` or a conversation in `messages`.
        core.register("vlm.infer_stream") { call in
            let vlm = try call.object("vlm", as: TSVLM.self)
            let config = BridgeCodec.llm_config(
                call.dict("config"), base: vlm.generation_defaults)
            let images = try Self.images(call)
            let system = call.string("system_prompt", default: nil)
            let chunks =
                if let items = call.params["messages"] as? [[String: Any]] {
                    try vlm.infer_stream(
                        images: images,
                        messages: try BridgeCodec.chat_messages(items).map {
                            $0.to_template_message()
                        },
                        system_prompt: system, config: config)
                } else {
                    try vlm.infer_stream(
                        images: images, prompt: try call.string("prompt"),
                        system_prompt: system, config: config)
                }
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
    }

    /// The call's images: files by path, then the body split by `image_lengths`.
    static func images(_ call: BridgeCall) throws -> [CGImage] {
        var out = try (call.params["image_paths"] as? [String] ?? []).map {
            try ImageIOHelpers.load_cgimage(path: $0)
        }
        var offset = call.body.startIndex
        for length in call.params["image_lengths"] as? [Int] ?? [] {
            guard offset + length <= call.body.endIndex else {
                throw BridgeError.protocol_error("image_lengths exceed the body")
            }
            out.append(
                try ImageIOHelpers.load_cgimage(
                    data: call.body.subdata(in: offset..<(offset + length))))
            offset += length
        }
        return out
    }
}
