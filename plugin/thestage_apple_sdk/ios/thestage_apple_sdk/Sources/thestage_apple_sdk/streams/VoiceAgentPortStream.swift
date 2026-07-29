@preconcurrency import Flutter
import Foundation
import TheStageCore

// --------------------------------------------------------------------------------------
// VoiceAgentPortStream
// --------------------------------------------------------------------------------------
@MainActor
final class VoiceAgentPortStream: NSObject, FlutterStreamHandler {

    // ----------------------------------------------------------------------------------
    // Private Attributes
    // ----------------------------------------------------------------------------------
    private var __agent_provider: (@MainActor () -> TheStageVoiceAgent?)?
    private var __sink: FlutterEventSink?
    private var __disconnects: [() -> Void] = []

    // ----------------------------------------------------------------------------------
    // Public Methods
    // ----------------------------------------------------------------------------------
    func configure(
        agent_provider: @escaping @MainActor () -> TheStageVoiceAgent?
    ) {
        __agent_provider = agent_provider
        if __sink != nil, let agent = agent_provider() {
            __bind(agent: agent)
        }
    }

    func bind(agent: TheStageVoiceAgent) {
        if __sink != nil {
            __bind(agent: agent)
        }
    }

    func unbind() {
        __teardown()
    }

    func register_node_port_forward(
        node: FlutterBridgeNode,
        port: String
    ) {
        guard let sink = __sink else { return }
        node.ensure_port_forward(port) { payload in
            DispatchQueue.main.async { sink(payload) }
        }
    }

    // ----------------------------------------------------------------------------------
    // FlutterStreamHandler
    // ----------------------------------------------------------------------------------
    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        __sink = events
        if let agent = __agent_provider?() {
            __bind(agent: agent)
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        __teardown()
        __sink = nil
        return nil
    }

    // ----------------------------------------------------------------------------------
    // Private Methods
    // ----------------------------------------------------------------------------------
    private func __bind(agent: TheStageVoiceAgent) {
        __teardown()
        guard let sink = __sink else { return }

        let emit: @Sendable ([String: Any]) -> Void = { payload in
            DispatchQueue.main.async { sink(payload) }
        }

        __connect_string_channel(agent.llm_deltas, "llm.delta", emit: emit)
        __connect_string_channel(agent.transcripts, "transcripts.final", emit: emit)
        __connect_string_channel(
            agent.partial_transcripts,
            "transcripts.partial",
            emit: emit
        )
        __connect_double_channel(
            agent.vad_probabilities,
            "vad.probability",
            emit: emit
        )
    }

    private func __connect_string_channel(
        _ channel: AgentChannel<String>,
        _ name: String,
        emit: @escaping @Sendable ([String: Any]) -> Void
    ) {
        let connector = AgentConnector(from: channel) { value in
            emit(["port": name, "value": value])
        }
        __disconnects.append { connector.disconnect() }
    }

    private func __connect_double_channel(
        _ channel: AgentChannel<Double>,
        _ name: String,
        emit: @escaping @Sendable ([String: Any]) -> Void
    ) {
        let connector = AgentConnector(from: channel) { value in
            emit(["port": name, "value": value])
        }
        __disconnects.append { connector.disconnect() }
    }

    private func __teardown() {
        for disconnect in __disconnects { disconnect() }
        __disconnects.removeAll()
    }
}
