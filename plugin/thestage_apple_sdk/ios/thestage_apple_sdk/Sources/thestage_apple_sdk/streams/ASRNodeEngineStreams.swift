@preconcurrency import Flutter
import Foundation
import TheStageCore

// --------------------------------------------------------------------------------------
// ASRNodeEngineStream
// --------------------------------------------------------------------------------------
/// One `AgentChannel` of a node-backed ``ASREngine`` exposed as a Flutter
/// broadcast stream. Deliberately the same shape as
/// ``VoiceAgentBroadcastStream``: Dart may subscribe before or after
/// `start()`, so the sink and the engine arrive independently and whichever
/// lands second opens the connector.
@MainActor
final class ASRNodeEngineStream: NSObject, FlutterStreamHandler {

    typealias OpenConnector = @MainActor (
        _ engine: ASREngine,
        _ sink: @escaping @Sendable (Any) -> Void
    ) -> @MainActor () -> Void

    // ----------------------------------------------------------------------------------
    // Private Attributes
    // ----------------------------------------------------------------------------------
    private let __engine_provider: @MainActor () -> ASREngine?
    private let __open: OpenConnector
    private var __sink: FlutterEventSink?
    private var __disconnect: (@MainActor () -> Void)?

    // ----------------------------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------------------------
    init(
        engine_provider: @escaping @MainActor () -> ASREngine?,
        open: @escaping OpenConnector
    ) {
        self.__engine_provider = engine_provider
        self.__open = open
    }

    deinit {}

    // ----------------------------------------------------------------------------------
    // Public Methods
    // ----------------------------------------------------------------------------------
    /// A channel whose element already crosses the Flutter boundary as-is
    /// (`String`, `Double`).
    static func passthrough<T: Sendable>(
        engine_provider: @escaping @MainActor () -> ASREngine?,
        port: @escaping @Sendable (ASREngine) -> AgentChannel<T>
    ) -> ASRNodeEngineStream {
        ASRNodeEngineStream(engine_provider: engine_provider) { engine, sink in
            let connector = AgentConnector(from: port(engine)) { value in
                sink(value)
            }
            return { connector.disconnect() }
        }
    }

    /// `ASRTurn` encoded with the same field set ``ASRStreamHandler`` emits, so
    /// both Flutter ASR surfaces hand Dart an identical turn shape.
    static func turns(
        engine_provider: @escaping @MainActor () -> ASREngine?
    ) -> ASRNodeEngineStream {
        ASRNodeEngineStream(engine_provider: engine_provider) { engine, sink in
            let connector = AgentConnector(from: engine.turns) { turn in
                sink(ASRNodeEngineStream.encode(turn))
            }
            return { connector.disconnect() }
        }
    }

    /// `nonisolated`: the connector's handler runs off the main actor, and
    /// this is a pure field mapping with no state to protect.
    nonisolated static func encode(_ turn: ASRTurn) -> [String: Any] {
        [
            "transcript": turn.transcript,
            "committed": turn.committed,
            "hypothesis": turn.hypothesis,
            "end_of_turn": turn.end_of_turn,
            "is_final": turn.end_of_turn,
        ]
    }

    /// Called when the engine is created or torn down. Rebinding while a sink
    /// is attached reopens the connector against the new engine.
    func bind(engine: ASREngine) {
        __disconnect?()
        __disconnect = nil
        if __sink != nil {
            __open_connector(engine: engine)
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
        if let engine = __engine_provider() {
            __open_connector(engine: engine)
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
    private func __open_connector(engine: ASREngine) {
        let sink = __sink
        __disconnect = __open(engine) { value in
            DispatchQueue.main.async {
                sink?(value)
            }
        }
    }
}
