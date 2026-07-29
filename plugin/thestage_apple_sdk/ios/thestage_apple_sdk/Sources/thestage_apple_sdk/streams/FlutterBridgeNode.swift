@preconcurrency import Flutter
import Foundation
import TheStageCore

// --------------------------------------------------------------------------------------
// FlutterBridgeNode
// --------------------------------------------------------------------------------------
/// Custom agent node that forwards lifecycle hooks to Dart via
/// ``MethodChannels/voiceAgentNodes``.
final class FlutterBridgeNode: TheStageAgentNode, @unchecked Sendable {

    // ----------------------------------------------------------------------------------
    // Private Attributes
    // ----------------------------------------------------------------------------------
    private let __run_when_states: Set<TheStageAgentState>
    private let __channel: FlutterMethodChannel
    private var __current_state: TheStageAgentState = .idle
    private var __event_task: Task<Void, Never>?
    private var __port_forwarders: [String: AgentConnector<String>] = [:]

    // ----------------------------------------------------------------------------------
    // Public Attributes
    // ----------------------------------------------------------------------------------
    override var run_when: Set<TheStageAgentState> { __run_when_states }

    var is_gate_open: Bool {
        if __run_when_states.isEmpty { return true }
        return __run_when_states.contains(__current_state)
    }

    // ----------------------------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------------------------
    init(
        id: String,
        run_when states: [TheStageAgentState],
        channel: FlutterMethodChannel
    ) {
        self.__run_when_states = Set(states)
        self.__channel = channel
        super.init(id: id)
    }

    deinit {
        __event_task?.cancel()
    }

    // ----------------------------------------------------------------------------------
    // Lifecycle
    // ----------------------------------------------------------------------------------
    override func on_start() async throws {
        __invoke(
            "voice_agent.node_on_start",
            [
                "id": id,
                "state": __current_state.rawValue,
                "is_gate_open": is_gate_open,
            ]
        )
        guard let stream = subscribe() else { return }
        __event_task = Task { [weak self] in
            for await event in stream {
                if Task.isCancelled { break }
                await self?.__handle_event(event)
            }
        }
    }

    override func on_stop() async {
        __event_task?.cancel()
        __event_task = nil
        for (_, connector) in __port_forwarders {
            connector.disconnect()
        }
        __port_forwarders.removeAll()
        __invoke(
            "voice_agent.node_on_stop",
            [
                "id": id,
                "state": __current_state.rawValue,
                "is_gate_open": is_gate_open,
            ]
        )
    }

    // ----------------------------------------------------------------------------------
    // Port I/O
    // ----------------------------------------------------------------------------------
    func send_port(_ name: String, value: String) {
        make_port(name).send(value)
    }

    func ensure_port_forward(
        _ name: String,
        sink: @escaping @Sendable ([String: Any]) -> Void
    ) {
        if __port_forwarders[name] != nil { return }
        let channel: AgentChannel<String> = make_port(name)
        let connector = AgentConnector(from: channel) { value in
            sink([
                "port": "\(self.id).\(name)",
                "value": value,
            ])
        }
        __port_forwarders[name] = connector
    }

    // ----------------------------------------------------------------------------------
    // Private Methods
    // ----------------------------------------------------------------------------------
    private func __handle_event(_ event: AgentEvent) async {
        switch event {
        case .STATE(let state):
            __current_state = state
            __invoke(
                "voice_agent.node_on_state",
                [
                    "id": id,
                    "state": state.rawValue,
                    "is_gate_open": is_gate_open,
                ]
            )
        default:
            __invoke(
                "voice_agent.node_on_event",
                [
                    "id": id,
                    "state": __current_state.rawValue,
                    "is_gate_open": is_gate_open,
                    "event": Self.__serialize_event(event),
                ]
            )
        }
    }

    private func __invoke(_ method: String, _ args: [String: Any]) {
        DispatchQueue.main.async { [channel = __channel] in
            channel.invokeMethod(method, arguments: args)
        }
    }

    private static func __serialize_event(_ event: AgentEvent) -> [String: Any] {
        switch event {
        case .SPEECH_STARTED(let prob):
            return ["kind": "SPEECH_STARTED", "prob": prob]
        case .SPEECH_ENDED(let silence_ms):
            return ["kind": "SPEECH_ENDED", "silence_ms": silence_ms]
        case .BARGE_IN(let prob, _):
            return ["kind": "BARGE_IN", "prob": prob]
        case .WAKE_WORD_DETECTED(let prob):
            return ["kind": "WAKE_WORD_DETECTED", "prob": prob]
        case .SPEAKER_VERIFIED(let similarity, _):
            return ["kind": "SPEAKER_VERIFIED", "similarity": similarity]
        case .SPEAKER_REJECTED(let similarity):
            return ["kind": "SPEAKER_REJECTED", "similarity": similarity]
        case .SPEECH_ONSET(let prob, _):
            return ["kind": "SPEECH_ONSET", "prob": prob]
        case .TURN_START_ACCEPTED:
            return ["kind": "TURN_START_ACCEPTED"]
        case .USER_REQUEST_PARTIAL(let text):
            return ["kind": "USER_REQUEST_PARTIAL", "text": text]
        case .USER_REQUEST(let text, let source):
            return [
                "kind": "USER_REQUEST",
                "text": text,
                "source": source.rawValue,
            ]
        case .RESPONSE_STARTED:
            return ["kind": "RESPONSE_STARTED"]
        case .RESPONSE_DONE(let text, let reason):
            return [
                "kind": "RESPONSE_DONE",
                "text": text,
                "reason": reason.rawValue,
            ]
        case .SYNTHESIS_DONE(let reason):
            return ["kind": "SYNTHESIS_DONE", "reason": reason.rawValue]
        case .PLAYBACK_STARTED:
            return ["kind": "PLAYBACK_STARTED"]
        case .PLAYBACK_ENDED(let reason):
            return ["kind": "PLAYBACK_ENDED", "reason": reason.rawValue]
        case .STATE(let state):
            return ["kind": "STATE", "state": state.rawValue]
        case .ERROR(let message):
            return ["kind": "ERROR", "message": message]
        }
    }
}
