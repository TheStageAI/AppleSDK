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

    func __handle_voice_agent_begin_listening(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let handler = __voice_agent_handler else {
            __fail(result, msg: "Voice agent handler not initialized.")
            return
        }
        Task { @MainActor in
            do {
                try await handler.begin_listening()
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
        let args = (call.arguments as? [String: Any]) ?? [:]
        // Accept either the pre-`voice_dir` shape (`{"voice": "paul"}`) or
        // the extended shape (`{"voice_id"/"voice_dir"/"language": ...}`).
        // Legacy `voice` is treated as `voice_id`.
        let voice_id = (args["voice_id"] as? String)
            ?? (args["voice"] as? String)
        let voice_dir = args["voice_dir"] as? String
        let language = args["language"] as? String
        if voice_id == nil && voice_dir == nil && language == nil {
            __fail(result, msg: "Pass voice_id, voice_dir or language.")
            return
        }
        Task { @MainActor in
            await __voice_agent_handler?.set_voice(
                voice_id: voice_id,
                voice_dir: voice_dir,
                language: language
            )
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

    func __handle_voice_agent_set_system_prompt(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let prompt = args["system_prompt"] as? String
        else {
            __fail(result, msg: "Missing system_prompt.")
            return
        }
        Task { [weak self] in
            await self?.__voice_agent_handler?.set_system_prompt(prompt)
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
        let mode = __parse_interrupt_mode(mode_str)
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

    func __handle_voice_agent_enroll_speaker(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let handler = __voice_agent_handler else {
            __fail(result, msg: "Voice agent handler not initialized.")
            return
        }
        let args = call.arguments as? [String: Any] ?? [:]
        let embedding = __parse_embedding(args["embedding"])
        Task { @MainActor in
            await handler.enroll_speaker(embedding: embedding)
            result(nil)
        }
    }

    func __handle_voice_agent_send_node_port(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let handler = __voice_agent_handler else {
            __fail(result, msg: "Voice agent handler not initialized.")
            return
        }
        guard let args = call.arguments as? [String: Any],
              let node_id = args["node_id"] as? String,
              let port = args["port"] as? String,
              let value = args["value"] as? String
        else {
            __fail(result, msg: "Missing node_id, port, or value.")
            return
        }
        handler.send_node_port(node_id: node_id, port: port, value: value)
        result(nil)
    }

    func __handle_voice_agent_publish_node_event(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let handler = __voice_agent_handler else {
            __fail(result, msg: "Voice agent handler not initialized.")
            return
        }
        guard let args = call.arguments as? [String: Any],
              let node_id = args["node_id"] as? String,
              let event = args["event"] as? [String: Any]
        else {
            __fail(result, msg: "Missing node_id or event.")
            return
        }
        handler.publish_node_event(node_id: node_id, event: event)
        result(nil)
    }

    func __handle_voice_agent_send_request(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let handler = __voice_agent_handler else {
            __fail(result, msg: "Voice agent handler not initialized.")
            return
        }
        guard let args = call.arguments as? [String: Any],
              let text = args["text"] as? String
        else {
            __fail(result, msg: "Missing text.")
            return
        }
        handler.send_request(text)
        result(nil)
    }
}
