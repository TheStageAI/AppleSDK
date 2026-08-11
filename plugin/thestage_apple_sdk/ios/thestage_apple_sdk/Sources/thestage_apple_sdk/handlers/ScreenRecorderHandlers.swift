@preconcurrency import Flutter
import Foundation
import TheStageCore

extension TheStageFlutterPlugin {
    func __handle_screen_recorder_is_recording(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        result(ScreenDemoRecorder.shared.recording)
    }

    func __handle_screen_recorder_start(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        Task { @MainActor in
            do {
                try await ScreenDemoRecorder.shared.start()
                result(nil)
            } catch {
                result(FlutterError(
                    code: "screen_recorder_start",
                    message: error.localizedDescription,
                    details: String(describing: error)
                ))
            }
        }
    }

    func __handle_screen_recorder_stop(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        Task { @MainActor in
            do {
                try await ScreenDemoRecorder.shared.stop()
                result(nil)
            } catch {
                result(FlutterError(
                    code: "screen_recorder_stop",
                    message: error.localizedDescription,
                    details: String(describing: error)
                ))
            }
        }
    }
}
