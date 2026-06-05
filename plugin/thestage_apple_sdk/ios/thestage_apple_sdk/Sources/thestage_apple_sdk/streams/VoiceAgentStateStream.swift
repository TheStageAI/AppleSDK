@preconcurrency import Flutter
import Foundation
import TheStageCore

// --------------------------------------------------------------------------------------
// VoiceAgentStateStream
// --------------------------------------------------------------------------------------
@MainActor
final class VoiceAgentStateStream: NSObject, FlutterStreamHandler {

    // ----------------------------------------------------------------------------------
    // Private Attributes
    // ----------------------------------------------------------------------------------
    private var __event_sink: FlutterEventSink?
    private var __agent: TheStageVoiceAgent?
    private var __event_task: Task<Void, Never>?
    private var __taps: [VoiceAgentBroadcastStream] = []

    // ----------------------------------------------------------------------------------
    // Public Methods
    // ----------------------------------------------------------------------------------
    var has_sink: Bool { __event_sink != nil }
    var agent: TheStageVoiceAgent? { __agent }

    func register_tap(_ tap: VoiceAgentBroadcastStream) {
        __taps.append(tap)
        if let agent = __agent { tap.bind(agent: agent) }
    }

    // ----------------------------------------------------------------------------------
    // FlutterStreamHandler
    // ----------------------------------------------------------------------------------
    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        __event_sink = events
        return nil
    }

    func onCancel(
        withArguments arguments: Any?
    ) -> FlutterError? {
        __event_task?.cancel()
        __event_task = nil
        __event_sink = nil
        return nil
    }

    // ----------------------------------------------------------------------------------
    // Lifecycle
    // ----------------------------------------------------------------------------------
    func start(config: [String: Any]) async throws {
        let agent_config = Self.__parse_config(config)
        let agent = TheStageVoiceAgent(config: agent_config)
        __agent = agent

        for tap in __taps { tap.bind(agent: agent) }

        let sink = __event_sink
        __event_task = Task.detached { [weak self] in
            for await event in agent.events {
                guard !Task.isCancelled else { break }
                var dict: [String: Any] = [
                    "kind": event.kind.rawValue,
                ]
                for (k, v) in event.data {
                    dict[k] = v
                }
                DispatchQueue.main.async {
                    sink?(dict)
                }
            }
            _ = self
        }

        try await agent.start()
    }

    func stop() async {
        __event_task?.cancel()
        __event_task = nil
        for tap in __taps { tap.unbind() }
        await __agent?.stop()
        __agent = nil
    }

    func interrupt() {
        __agent?.interrupt()
    }

    func say(_ text: String) {
        __agent?.say(text)
    }

    func set_voice(_ voice: String) async {
        await __agent?.set_voice(voice)
    }

    func clear_history() async {
        await __agent?.clear_history()
    }

    func update_interrupt_config(
        min_speech_ms: Int?,
        min_playback_ms: Int?,
        mode: InterruptTrigger?
    ) async {
        await __agent?.update_interrupt_config(
            min_speech_ms: min_speech_ms,
            min_playback_ms: min_playback_ms,
            mode: mode
        )
    }

    // ----------------------------------------------------------------------------------
    // Private Methods
    // ----------------------------------------------------------------------------------
    private static func __parse_config(
        _ dict: [String: Any]
    ) -> TheStageAgentConfig {
        let llm: TheStageLLMProvider
        let provider_type =
            dict["llm_provider"] as? String ?? "openai_compatible"

        if provider_type == "local" {
            llm = TheStageLocalLLMProvider(
                model_path: dict["llm_model"] as? String ?? ""
            )
        } else {
            llm = TheStageOpenAICompatibleProvider(
                endpoint: dict["llm_endpoint"] as? String
                    ?? "https://api.openai.com/v1/chat/completions",
                api_key: dict["llm_api_key"] as? String ?? "",
                model: dict["llm_model"] as? String ?? "gpt-4o-mini"
            )
        }

        var config = TheStageAgentConfig(
            vad: dict["vad"] as? String ?? "TheStageAI/silero-vad",
            stt: dict["stt"] as? String
                ?? "TheStageAI/thewhisper-large-v3-turbo",
            tts: dict["tts"] as? String
                ?? "TheStageAI/neutts-multilingual",
            llm: llm,
            wake_word: dict["wake_word"] as? String
        )

        if let v = dict["tts_voice"] as? String {
            config.tts_voice = v
        }
        if let v = dict["system_prompt"] as? String {
            config.system_prompt = v
        }
        if let v = dict["max_tokens"] as? Int {
            config.max_tokens = v
        }
        if let v = dict["temperature"] as? Double {
            config.temperature = v
        }
        if let v = dict["vad_threshold"] as? Double {
            config.vad_threshold = v
        }
        if let v = dict["silence_timeout_ms"] as? Int {
            config.silence_timeout_frames = max(1, v / 32)
        }
        if let v = dict["allow_interruptions"] as? Bool {
            config.allow_interruptions = v
        }
        if let v = dict["interrupt_mode"] as? String {
            switch v {
            case "none":      config.interrupt_mode = .none
            case "wake_word": config.interrupt_mode = .wake_word
            default:          config.interrupt_mode = .speech_only
            }
        }
        if let v = dict["interrupt_min_speech_ms"] as? Int {
            config.interrupt_min_speech_ms = v
        }
        if let v = dict["pre_roll_ms"] as? Int {
            config.pre_roll_ms = v
        }
        if let v = dict["aec_enabled"] as? Bool {
            config.aec_enabled = v
        }
        if let v = dict["speculative_whisper"] as? Bool {
            config.speculative_whisper = v
        }
        if let v = dict["ww_threshold"] as? Double {
            config.ww_threshold = v
        }
        if let v = dict["conversation_timeout_sec"] as? Int {
            config.conversation_timeout_sec = v
        }
        if let v = dict["stt_language"] as? String {
            config.stt_language = v
        }

        if let v = dict["vad_device"] as? String {
            config.vad_device = v
        }
        if let v = dict["stt_device"] as? String {
            config.stt_device = v
        }
        if let v = dict["tts_device"] as? String {
            config.tts_device = v
        }
        if let v = dict["ww_device"] as? String {
            config.ww_device = v
        }
        if let v = __parse_devices(dict["stt_devices"]) {
            config.stt_devices = v
        }
        if let v = __parse_devices(dict["tts_devices"]) {
            config.tts_devices = v
        }

        if let v = dict["stt_revision"] as? String {
            config.stt_revision = v
        }
        if let v = dict["tts_revision"] as? String {
            config.tts_revision = v
        }

        return config
    }
}
