@preconcurrency import Flutter
import Foundation
import TheStageCore

// --------------------------------------------------------------------------------------
// Inference Handlers
// --------------------------------------------------------------------------------------
extension TheStageFlutterPlugin {

    func __handle_infer(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let model_name = args["model_name"] as? String
        else {
            __fail(result, msg: "Missing model_name.")
            return
        }

        let input_json = args["input_json"]
            as? [String: Any] ?? args
        let normalized = __normalize(input_json)
            as? [String: Any] ?? input_json

        Task { @MainActor in
            do {
                if let vad_name = input_json["vad_model_name"] as? String,
                   !vad_name.isEmpty,
                   let pcm = __pcm(
                    from: input_json["audio"] ?? input_json["pcm"]
                   ) {
                    let generation = __decode_generation(normalized)
                    let asr = try await ASREngine(
                        stt: model_name, vad: vad_name
                    ).infer(audio: pcm, config: generation)
                    result([__encode_asr_result(asr)])
                    return
                }
                let response = try TheStageAI.shared.infer(
                    model_name: model_name,
                    input_json: normalized
                )
                result(response)
            } catch {
                __fail(result, error: error)
            }
        }
    }

    func __handle_start_stream(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let model_name = args["model_name"] as? String,
              let stream_id = args["stream_id"] as? String
        else {
            __fail(result, msg: "Missing model_name or stream_id.")
            return
        }
        guard let handler = __stream_handler else {
            __fail(result, msg: "Stream channel not ready.")
            return
        }

        let input_json = args["input_json"]
            as? [String: Any] ?? [:]
        let kind = (args["kind"] as? String)?.lowercased()
            ?? __infer_kind(input_json)

        let sink_status = handler.has_sink ? "sink_SET" : "sink_NIL"
        if kind == "asr" {
            __asr_handler?.start(
                stream_id: stream_id,
                model_name: model_name,
                input_json: input_json
            )
        } else {
            handler.start(
                stream_id: stream_id,
                model_name: model_name,
                input_json: input_json
            )
        }
        result(["sink_status": sink_status])
    }

    func __handle_send_stream(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let stream_id = args["stream_id"] as? String
        else {
            __fail(result, msg: "Missing stream_id.")
            return
        }
        if let pcm = __pcm(from: args["pcm"]) {
            __asr_handler?.send(stream_id: stream_id, pcm: pcm)
        } else if let text = args["text"] as? String {
            __stream_handler?.send(stream_id: stream_id, text: text)
        } else {
            __fail(result, msg: "Missing stream_id payload (text or pcm).")
            return
        }
        result(nil)
    }

    func __handle_flush_stream(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let stream_id = args["stream_id"] as? String
        else {
            __fail(result, msg: "Missing stream_id.")
            return
        }
        if __asr_handler?.has(stream_id) == true {
            __asr_handler?.flush(stream_id: stream_id)
        } else {
            __stream_handler?.flush(stream_id: stream_id)
        }
        result(nil)
    }

    func __handle_finish_stream(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let stream_id = args["stream_id"] as? String
        else {
            __fail(result, msg: "Missing stream_id.")
            return
        }
        if __asr_handler?.has(stream_id) == true {
            Task { @MainActor in
                let asr = await __asr_handler?.close(stream_id: stream_id)
                    ?? .empty
                result(__encode_asr_result(asr))
            }
            return
        }
        __stream_handler?.finish_stream(stream_id: stream_id)
        result(nil)
    }

    func __handle_stop_stream(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let stream_id = args["stream_id"] as? String
        else {
            __fail(result, msg: "Missing stream_id.")
            return
        }
        if __asr_handler?.has(stream_id) == true {
            __asr_handler?.cancel(stream_id: stream_id)
        } else {
            __stream_handler?.cancel(stream_id: stream_id)
        }
        result(nil)
    }

    private func __infer_kind(_ input_json: [String: Any]) -> String {
        if input_json["pcm"] != nil || input_json["audio"] != nil {
            return "asr"
        }
        return "tts"
    }

    private func __decode_generation(
        _ payload: [String: Any]
    ) -> ASRGenerationConfig {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(
                withJSONObject: payload
              ),
              let decoded = try? JSONDecoder().decode(
                ASRGenerationConfig.self, from: data
              )
        else { return ASRGenerationConfig() }
        return decoded
    }

    private func __pcm(from value: Any?) -> [Float]? {
        if let typed = value as? FlutterStandardTypedData {
            let data = typed.data
            let count = data.count / MemoryLayout<Float>.size
            guard count > 0 else { return [] }
            return data.withUnsafeBytes { raw in
                Array(raw.bindMemory(to: Float.self).prefix(count))
            }
        }
        if let list = value as? [NSNumber] {
            return list.map { $0.floatValue }
        }
        return nil
    }

    private func __encode_asr_result(_ r: ASRResult) -> [String: Any] {
        var payload: [String: Any] = [
            "text": r.text,
            "timestamp_mode": r.timestamp_mode.rawValue,
            "generated_tokens": r.generated_tokens,
            "token_count": r.generated_tokens,
            "decode_seconds": r.decode_seconds,
        ]
        if let language = r.language { payload["language"] = language }
        if let tokens = r.tokens { payload["tokens"] = tokens }
        if let words = r.words {
            payload["words"] = words.map {
                [
                    "text": $0.text,
                    "t0": $0.t0,
                    "t1": $0.t1,
                ] as [String: Any]
            }
        }
        payload["metrics"] = [
            "preprocess_seconds": r.metrics.preprocess_seconds,
            "encode_seconds": r.metrics.encode_seconds,
            "decode_seconds": r.metrics.decode_seconds,
            "last_prefill_seconds": r.metrics.last_prefill_seconds,
            "total_seconds": r.metrics.total_seconds,
            "audio_seconds": r.metrics.audio_seconds,
            "rtf": r.metrics.rtf,
            "tokens_per_second": r.metrics.tokens_per_second,
            "chunk_count": r.metrics.chunk_count,
            "generated_tokens": r.metrics.generated_tokens,
        ]
        return payload
    }
}
