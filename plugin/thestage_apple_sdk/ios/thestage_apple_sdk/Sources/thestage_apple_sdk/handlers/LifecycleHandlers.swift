@preconcurrency import Flutter
import Foundation
import TheStageCore

// --------------------------------------------------------------------------------------
// Lifecycle Handlers
// --------------------------------------------------------------------------------------
extension TheStageFlutterPlugin {

    func __handle_initialize(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let api_token = args["api_token"] as? String
        else {
            __fail(result, msg: "Missing api_token.")
            return
        }
        Task { @MainActor in
            do {
                try await TheStageAI.shared.initialize(
                    apiToken: api_token
                )
                result(nil)
            } catch {
                __fail(result, error: error)
            }
        }
    }

    func __handle_start_model(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let model_name = args["model_name"] as? String,
              let engines_path = args["engines_path"] as? String
        else {
            __fail(result, msg: "Missing model_name or engines_path.")
            return
        }

        let model_type = args["model_type"] as? String
        let device = args["device"] as? String ?? "gpu"
        let devices = __parse_devices(args["devices"])
        let config = args["config"] as? [String: Any]
        let revision = args["revision"] as? String ?? "main"
        let phonemizer = __make_phonemizer(
            model_type: model_type, config: config
        )

        var on_load_progress: LoadProgressHandler? = nil
        if let sink = self.__progress_sink {
            on_load_progress = { event in
                DispatchQueue.main.async {
                    sink([
                        "model_name": model_name,
                        "phase": event.phase.rawValue,
                        "progress": event.fraction,
                    ])
                }
            }
        }

        Task { @MainActor in
            do {
                let status = try await TheStageAI.shared.start_model(
                    model_name: model_name,
                    engines_path: engines_path,
                    model_type: model_type,
                    device: device,
                    devices: devices,
                    config: config,
                    phonemizer: phonemizer,
                    revision: revision,
                    on_load_progress: on_load_progress
                )
                result(try __encode(status))
            } catch {
                __fail(result, error: error)
            }
        }
    }

    func __handle_stop_model(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let model_name = args["model_name"] as? String
        else {
            __fail(result, msg: "Missing model_name.")
            return
        }
        Task { @MainActor in
            do {
                let status = try TheStageAI.shared.stop_model(
                    model_name: model_name
                )
                result(try __encode(status))
            } catch {
                __fail(result, error: error)
            }
        }
    }
}
