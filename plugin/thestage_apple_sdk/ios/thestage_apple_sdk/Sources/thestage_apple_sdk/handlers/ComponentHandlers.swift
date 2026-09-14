@preconcurrency import Flutter
import Foundation
import TheStageCore

// --------------------------------------------------------------------------------------
// Component Handlers
// --------------------------------------------------------------------------------------
extension TheStageFlutterPlugin {

    func __handle_list_components(
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
                let statuses = try TheStageAI.shared.list_components(
                    model_name: model_name
                )
                result(try __encode_value(statuses))
            } catch {
                __fail(result, error: error)
            }
        }
    }

    func __handle_load_components(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        __handle_component_mutation(call, result: result) { name, ids in
            try await TheStageAI.shared.load_components(
                model_name: name, ids: ids
            )
        }
    }

    func __handle_unload_components(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        __handle_component_mutation(call, result: result) { name, ids in
            try await TheStageAI.shared.unload_components(
                model_name: name, ids: ids
            )
        }
    }

    private func __handle_component_mutation(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult,
        action: @escaping (
            String, [String]
        ) async throws -> [ModelComponentStatus]
    ) {
        guard let args = call.arguments as? [String: Any],
              let name = args["model_name"] as? String
        else {
            __fail(result, msg: "Missing model_name.")
            return
        }
        let ids = args["component_ids"] as? [String] ?? []
        Task { @MainActor in
            do {
                let r = try await action(name, ids)
                result(try __encode_value(r))
            } catch {
                __fail(result, error: error)
            }
        }
    }

    func __handle_bundled_engine_path(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let filename = args["filename"] as? String
        else {
            result(nil)
            return
        }
        let stem = filename
            .replacingOccurrences(of: ".zip", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // A sealed pack shipped as-is: BundledModels/<name>.thestage next to
        // its `<name>.qlip_bundle.json` sidecar. The SDK opens the archive
        // in place and extracts into its own cache, so the app carries the
        // exact artifact that was verified and published -- no unpacked
        // tree to drift from it.
        if let u = Bundle.main.url(
            forResource: stem,
            withExtension: "thestage",
            subdirectory: "BundledModels"
        ) {
            result(u.path)
            return
        }

        // Prefer directory bundles under BundledModels/<name>/ (v2 prepare).
        if let u = Bundle.main.url(
            forResource: stem,
            withExtension: nil,
            subdirectory: "BundledModels"
        ) {
            result(u.path)
            return
        }
        if let root = Bundle.main.resourceURL?
            .appendingPathComponent("BundledModels", isDirectory: true)
            .appendingPathComponent(stem, isDirectory: true),
           FileManager.default.fileExists(atPath: root.path) {
            result(root.path)
            return
        }

        // Legacy: a zip sitting at the app-bundle root.
        if let path = Bundle.main.path(
            forResource: stem,
            ofType: "zip"
        ) {
            result(path)
            return
        }
        result(nil)
    }
}
