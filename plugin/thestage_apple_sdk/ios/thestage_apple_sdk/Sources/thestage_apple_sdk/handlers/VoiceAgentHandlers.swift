@preconcurrency import Flutter
import Foundation
import TheStageCore

// --------------------------------------------------------------------------------------
// Voice Agent Handlers
// --------------------------------------------------------------------------------------
extension TheStageFlutterPlugin {

    func __handle_voice_agent_start(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let handler = __voice_agent_handler else {
            __fail(result, msg: "Voice agent handler not initialized.")
            return
        }
        let config = call.arguments as? [String: Any] ?? [:]
        Task { @MainActor in
            do {
                try await handler.start(config: config)
                result(nil)
            } catch {
                __fail(result, error: error)
            }
        }
    }

    func __handle_voice_agent_stop(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let handler = __voice_agent_handler else {
            result(nil)
            return
        }
        Task { @MainActor in
            await handler.stop()
            result(nil)
        }
    }

    func __handle_voice_agent_interrupt(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        __voice_agent_handler?.interrupt()
        result(nil)
    }

    func __handle_voice_agent_say(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let text = args["text"] as? String
        else {
            __fail(result, msg: "Missing text.")
            return
        }
        __voice_agent_handler?.say(text)
        result(nil)
    }

    func __handle_voice_agent_set_voice(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let voice = args["voice"] as? String
        else {
            __fail(result, msg: "Missing voice.")
            return
        }
        Task { @MainActor in
            await __voice_agent_handler?.set_voice(voice)
            result(nil)
        }
    }

    func __handle_voice_agent_clear_history(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        Task { [weak self] in
            await self?.__voice_agent_handler?.clear_history()
            result(nil)
        }
    }

    func __handle_voice_agent_update_interrupt_config(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        let args = call.arguments as? [String: Any] ?? [:]
        let min_speech_ms = args["interrupt_min_speech_ms"] as? Int
        let min_playback_ms = args["interrupt_min_playback_ms"] as? Int
        let onset_ms = args["interrupt_onset_ms"] as? Int
        let threshold = args["interrupt_threshold"] as? Double
        let mode_str = args["interrupt_mode"] as? String
        let mode: InterruptTrigger?
        switch mode_str {
        case "none":         mode = InterruptTrigger.none
        case "wake_word":    mode = .wake_word
        case "speech_only":  mode = .speech_only
        default:             mode = nil
        }
        Task { [weak self] in
            await self?.__voice_agent_handler?.update_interrupt_config(
                min_speech_ms: min_speech_ms,
                min_playback_ms: min_playback_ms,
                mode: mode,
                onset_ms: onset_ms,
                threshold: threshold
            )
            result(nil)
        }
    }
}
