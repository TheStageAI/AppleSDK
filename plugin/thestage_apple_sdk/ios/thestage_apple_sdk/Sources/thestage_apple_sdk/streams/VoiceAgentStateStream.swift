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
    private var __bridge_nodes: [FlutterBridgeNode] = []
    private var __node_channel: FlutterMethodChannel?
    private weak var __port_stream: VoiceAgentPortStream?

    // ----------------------------------------------------------------------------------
    // Public Methods
    // ----------------------------------------------------------------------------------
    var has_sink: Bool { __event_sink != nil }
    var agent: TheStageVoiceAgent? { __agent }
    var bridge_nodes: [FlutterBridgeNode] { __bridge_nodes }

    func configure(
        node_channel: FlutterMethodChannel,
        port_stream: VoiceAgentPortStream
    ) {
        __node_channel = node_channel
        __port_stream = port_stream
    }

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
        let agent_config = Self.__parse_config(
            config,
            node_channel: __node_channel,
            bridge_nodes: &__bridge_nodes
        )
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
        __port_stream?.bind(agent: agent)
    }

    func begin_listening() async throws {
        try await __agent?.begin_listening()
    }

    func stop() async {
        __event_task?.cancel()
        __event_task = nil
        for tap in __taps { tap.unbind() }
        __port_stream?.unbind()
        await __agent?.stop()
        __agent = nil
        __bridge_nodes.removeAll()
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
        mode: InterruptMode?,
        onset_ms: Int? = nil,
        threshold: Double? = nil
    ) async {
        await __agent?.update_interrupt_config(
            min_speech_ms: min_speech_ms,
            min_playback_ms: min_playback_ms,
            interrupt_mode: mode,
            onset_ms: onset_ms,
            threshold: threshold
        )
    }

    func enroll_speaker(embedding: [Double]?) async {
        await __agent?.enroll_speaker(embedding)
    }

    func send_node_port(node_id: String, port: String, value: String) {
        guard let node = __bridge_nodes.first(where: { $0.id == node_id })
        else { return }
        __port_stream?.register_node_port_forward(node: node, port: port)
        node.send_port(port, value: value)
    }

    // ----------------------------------------------------------------------------------
    // Private Methods
    // ----------------------------------------------------------------------------------
    private static func __parse_config(
        _ dict: [String: Any],
        node_channel: FlutterMethodChannel?,
        bridge_nodes: inout [FlutterBridgeNode]
    ) -> TheStageAgentConfig {
        bridge_nodes.removeAll()
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
                ?? "TheStageAI/neutts-nano-multilingual",
            llm: llm,
            wake_word: dict["wake_word"] as? String
        )

        if let v = dict["tts_voice"] as? String {
            config.tts_voice = v
        }
        if let v = dict["system_prompt"] as? String {
            config.system_prompt = v
        }
        if let v = dict["chat_memory_max_turns"] as? Int, v > 0 {
            config.chat_memory = TheStageSlidingWindowMemory(max_turns: v)
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
        if let v = dict["interrupt_threshold"] as? Double {
            config.interrupt_threshold = v
        }
        if let v = dict["silence_timeout_ms"] as? Int {
            config.silence_timeout_ms = v
        }
        if let v = dict["allow_interruptions"] as? Bool {
            config.allow_interruptions = v
        }
        if let v = __parse_interrupt_mode(dict["interrupt_mode"]) {
            config.interrupt_mode = v
        }
        if let v = __parse_turn_start_mode(dict["turn_start_mode"]) {
            config.turn_start_mode = v
        }
        if let v = __parse_turn_end_mode(dict["turn_end_mode"]) {
            config.turn_end_mode = v
        } else if let v = __parse_turn_end_mode(dict["turn_detection_mode"]) {
            config.turn_detection_mode = v
        }
        if let v = dict["speaker_id"] as? String {
            config.speaker_id = v
        }
        if let v = dict["speaker_id_device"] as? String {
            config.speaker_id_device = v
        }
        if let v = dict["speaker_similarity_threshold"] as? Double {
            config.speaker_similarity_threshold = v
        }
        if let v = __parse_embedding(dict["enrolled_speaker_embedding"]) {
            config.enrolled_speaker_embedding = v
        }
        if let v = dict["ww_threshold_score"] as? Double {
            config.ww_threshold_score = v
        }
        if let v = dict["interrupt_min_speech_ms"] as? Int {
            config.interrupt_min_speech_ms = v
        }
        if let v = dict["interrupt_onset_ms"] as? Int {
            config.interrupt_onset_ms = v
        }
        if let v = dict["interrupt_min_playback_ms"] as? Int {
            config.interrupt_min_playback_ms = v
        }
        if let v = dict["interrupt_initial_lockout_ms"] as? Int {
            config.interrupt_initial_lockout_ms = v
        }
        if let v = dict["interrupt_thinking_lockout_ms"] as? Int {
            config.interrupt_thinking_lockout_ms = v
        }
        if let v = dict["pre_roll_ms"] as? Int {
            config.pre_roll_ms = v
        }
        if let v = dict["vad_onset_ms"] as? Int {
            config.vad_onset_ms = v
        }
        if let v = dict["max_accumulation_ms"] as? Int {
            config.max_accumulation_ms = v
        }
        if let v = dict["auto_listen"] as? Bool {
            config.auto_listen = v
        }
        if let v = dict["aec_enabled"] as? Bool {
            config.aec_enabled = v
        }
        if let v = dict["aec_warmup_ms"] as? Int {
            config.aec_warmup_ms = v
        }
        if let v = dict["aec_playback_gate_tail_ms"] as? Int {
            config.aec_playback_gate_tail_ms = v
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

        if let v = dict["turn_detector"] as? String {
            config.turn_detector = v
        }
        if let v = dict["turn_detector_device"] as? String {
            config.turn_detector_device = v
        }
        if let v = dict["turn_detector_revision"] as? String {
            config.turn_detector_revision = v
        }
        if let v = dict["turn_eot_threshold"] as? Double {
            config.turn_eot_threshold = v
        }
        if let v = dict["turn_eot_confirm_count"] as? Int {
            config.turn_eot_confirm_count = v
        }
        if let v = dict["turn_eot_high_confidence"] as? Double {
            config.turn_eot_high_confidence = v
        }
        if let v = dict["turn_pause_trigger_ms"] as? Int {
            config.turn_pause_trigger_ms = v
        }
        if let v = dict["turn_reeval_interval_ms"] as? Int {
            config.turn_reeval_interval_ms = v
        }
        if let v = dict["turn_max_silence_ms"] as? Int {
            config.turn_max_silence_ms = v
        }
        if let v = dict["turn_window_ms"] as? Int {
            config.turn_window_ms = v
        }
        if let v = dict["turn_min_speech_ms"] as? Int {
            config.turn_min_speech_ms = v
        }
        if let v = dict["turn_asr_silence_hangover_ms"] as? Int {
            config.turn_asr_silence_hangover_ms = v
        }

        // Streaming ASR toggles live caption partials; the authoritative
        // end-of-turn transcript is identical either way.
        if let v = dict["asr_streaming"] as? Bool {
            config.asr_streaming = v
        }
        if let v = dict["asr_partial_interval_ms"] as? Int {
            config.asr_partial_interval_ms = v
        }
        if let v = dict["debug_timeline"] as? Bool {
            config.debug_timeline = v
        }

        if let channel = node_channel,
           let nodes = dict["extra_nodes"] as? [[String: Any]] {
            var parsed: [FlutterBridgeNode] = []
            parsed.reserveCapacity(nodes.count)
            for desc in nodes {
                guard let id = desc["id"] as? String else { continue }
                let run_when = __parse_agent_states(desc["run_when"])
                parsed.append(
                    FlutterBridgeNode(
                        id: id,
                        run_when: run_when,
                        channel: channel
                    )
                )
            }
            bridge_nodes = parsed
            config.extra_nodes = parsed
        }

        return config
    }
}
