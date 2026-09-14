@preconcurrency import Flutter
import Foundation
import TheStageCore

// --------------------------------------------------------------------------------------
// VoiceAgentBroadcastStream
// --------------------------------------------------------------------------------------
@MainActor
final class VoiceAgentBroadcastStream: NSObject, FlutterStreamHandler {

    typealias OpenConnector = @MainActor (
        _ agent: TSVoiceAgent,
        _ sink: @escaping @Sendable (Any) -> Void
    ) -> @MainActor () -> Void

    // ----------------------------------------------------------------------------------
    // Private Attributes
    // ----------------------------------------------------------------------------------
    private let __agent_provider: @MainActor () -> TSVoiceAgent?
    private let __open: OpenConnector
    private var __sink: FlutterEventSink?
    private var __disconnect: (@MainActor () -> Void)?

    // ----------------------------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------------------------
    init(
        agent_provider: @escaping @MainActor () -> TSVoiceAgent?,
        open: @escaping OpenConnector
    ) {
        self.__agent_provider = agent_provider
        self.__open = open
    }

    // ----------------------------------------------------------------------------------
    // Public Methods
    // ----------------------------------------------------------------------------------
    static func string(
        agent_provider: @escaping @MainActor () -> TSVoiceAgent?,
        port: @escaping @Sendable (TSVoiceAgent) -> AgentChannel<String>
    ) -> VoiceAgentBroadcastStream {
        VoiceAgentBroadcastStream(
            agent_provider: agent_provider
        ) { agent, sink in
            let connector = AgentConnector(from: port(agent)) { value in
                sink(value)
            }
            return { connector.disconnect() }
        }
    }

    static func double(
        agent_provider: @escaping @MainActor () -> TSVoiceAgent?,
        port: @escaping @Sendable (TSVoiceAgent) -> AgentChannel<Double>
    ) -> VoiceAgentBroadcastStream {
        VoiceAgentBroadcastStream(
            agent_provider: agent_provider
        ) { agent, sink in
            let connector = AgentConnector(from: port(agent)) { value in
                sink(value)
            }
            return { connector.disconnect() }
        }
    }

    func bind(agent: TSVoiceAgent) {
        __disconnect?()
        __disconnect = nil
        if __sink != nil {
            __open_connector(agent: agent)
        }
    }

    func unbind() {
        __disconnect?()
        __disconnect = nil
    }

    // ----------------------------------------------------------------------------------
    // FlutterStreamHandler
    // ----------------------------------------------------------------------------------
    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        __sink = events
        if let agent = __agent_provider() {
            __open_connector(agent: agent)
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        __disconnect?()
        __disconnect = nil
        __sink = nil
        return nil
    }

    // ----------------------------------------------------------------------------------
    // Private Methods
    // ----------------------------------------------------------------------------------
    private func __open_connector(agent: TSVoiceAgent) {
        let sink = __sink
        __disconnect = __open(agent) { value in
            DispatchQueue.main.async {
                sink?(value)
            }
        }
    }
}
