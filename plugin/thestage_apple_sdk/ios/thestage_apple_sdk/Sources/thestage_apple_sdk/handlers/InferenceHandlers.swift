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

        let sink_status = handler.has_sink ? "sink_SET" : "sink_NIL"
        handler.start(
            stream_id: stream_id,
            model_name: model_name,
            input_json: input_json
        )
        result(["sink_status": sink_status])
    }

    func __handle_send_stream(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let stream_id = args["stream_id"] as? String,
              let text = args["text"] as? String
        else {
            __fail(result, msg: "Missing stream_id or text.")
            return
        }
        __stream_handler?.send(stream_id: stream_id, text: text)
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
        __stream_handler?.cancel(stream_id: stream_id)
        result(nil)
    }
}
