@preconcurrency import Flutter
import Foundation
import TheStageCore

// --------------------------------------------------------------------------------------
// ASRNodeEngineHandlers
// --------------------------------------------------------------------------------------
/// Bridges the node-backed ``ASREngine/init(config:)`` to Dart.
///
/// Unlike ``ASRStreamHandler`` — which is the *Current* push path, where Dart
/// owns the microphone and feeds PCM — this owns the whole lifecycle natively:
/// audio node, VAD, turn policy and one persistent decoder stream. Dart
/// supplies model paths as strings and reads typed streams. That is the same
/// division of labour ``VoiceAgentHandlers`` already uses.
///
/// Model loading is *not* done here: `TSAgentConfig.stt` / `.vad` are HF paths
/// and ``ASREngineBackend`` resolves them through `TheStageAI.shared`, records
/// what it loaded, and releases it on `stop()`. Passing already-loaded objects
/// would take that ownership away from the SDK.
@MainActor
final class ASRNodeEngineHandlers {

    // ----------------------------------------------------------------------------------
    // Private Attributes
    // ----------------------------------------------------------------------------------
    private var __engine: ASREngine?
    private let __streams: [ASRNodeEngineStream]

    // ----------------------------------------------------------------------------------
    // Public Attributes
    // ----------------------------------------------------------------------------------
    let turns: ASRNodeEngineStream
    let transcripts: ASRNodeEngineStream
    let partials: ASRNodeEngineStream
    let vad_probabilities: ASRNodeEngineStream
    let events: ASRNodeEngineStream

    // ----------------------------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------------------------
    init() {
        // Boxed so every stream shares one engine reference that `start` fills
        // in later — Dart is free to subscribe before `start()` is called.
        let box = __EngineBox()
        let provider: @MainActor () -> ASREngine? = { box.engine }

        self.turns = ASRNodeEngineStream.turns(engine_provider: provider)
        self.transcripts = ASRNodeEngineStream.passthrough(
            engine_provider: provider,
            port: { $0.transcripts }
        )
        self.partials = ASRNodeEngineStream.passthrough(
            engine_provider: provider,
            port: { $0.partial_transcripts }
        )
        self.vad_probabilities = ASRNodeEngineStream.passthrough(
            engine_provider: provider,
            port: { $0.vad_probabilities }
        )
        self.events = ASRNodeEngineStream(engine_provider: provider) {
            engine, sink in
            let task = Task { @MainActor in
                for await event in engine.events {
                    if Task.isCancelled { break }
                    sink([
                        "kind": event.kind.rawValue,
                        "data": event.data,
                    ])
                }
            }
            return { task.cancel() }
        }
        self.__streams = [
            turns, transcripts, partials, vad_probabilities, events,
        ]
        self.__box = box
    }

    deinit {}

    // ----------------------------------------------------------------------------------
    // Public Methods
    // ----------------------------------------------------------------------------------
    func start(_ dict: [String: Any]) async throws {
        await stop()
        let engine = ASREngine(config: Self.config(from: dict))
        __engine = engine
        __box.engine = engine
        for stream in __streams { stream.bind(engine: engine) }
        do {
            try await engine.start()
        } catch {
            // Leave nothing half-attached: a failed start must look exactly
            // like never having started, or the next start() inherits sinks
            // wired to a dead engine.
            for stream in __streams { stream.unbind() }
            __engine = nil
            __box.engine = nil
            throw error
        }
    }

    func stop() async {
        for stream in __streams { stream.unbind() }
        let engine = __engine
        __engine = nil
        __box.engine = nil
        await engine?.stop()
    }

    var is_running: Bool { __engine != nil }

    /// Maps the Dart config map onto ``TSAgentConfig``.
    ///
    /// Every key is optional and an absent key leaves the SDK's shipping
    /// policy alone — that is why each assignment is guarded rather than
    /// defaulted here. The streaming knobs (`ASRStreamingConfig`, `VADConfig`,
    /// the commit ladder) are deliberately not exposed: they are easy to
    /// misconfigure and the tuned policy is the point.
    static func config(from dict: [String: Any]) -> TSAgentConfig {
        var config = TSAgentConfig(
            vad: dict["vad"] as? String ?? "TheStageAI/silero-vad",
            stt: dict["stt"] as? String
                ?? "TheStageAI/thewhisper-large-v3-turbo"
        )
        if let v = dict["vad_device"] as? String, !v.isEmpty {
            config.vad_device = v
        }
        if let v = dict["stt_device"] as? String, !v.isEmpty {
            config.stt_device = v
        }
        if let v = dict["stt_revision"] as? String, !v.isEmpty {
            config.stt_revision = v
        }
        if let v = dict["language"] as? String, !v.isEmpty {
            config.asr_generation.language = v
        }
        var turn = config.turn_config ?? TurnConfig()
        var touched_turn = false
        if let v = __int(dict["turn_silence_timeout_ms"]) {
            turn.silence_timeout_ms = v
            touched_turn = true
        }
        if let v = __int(dict["turn_asr_silence_hangover_ms"]) {
            turn.asr_silence_hangover_ms = v
            touched_turn = true
        }
        if touched_turn { config.turn_config = turn }
        return config
    }

    // ----------------------------------------------------------------------------------
    // Private Methods
    // ----------------------------------------------------------------------------------
    /// Flutter hands integers across as `Int` on some platforms and
    /// `NSNumber` on others; both must map.
    private static func __int(_ value: Any?) -> Int? {
        if let v = value as? Int { return v }
        if let v = value as? NSNumber { return v.intValue }
        return nil
    }

    private let __box: __EngineBox

    // ----------------------------------------------------------------------------------
    // __EngineBox
    // ----------------------------------------------------------------------------------
    /// Shared mutable engine reference handed to every stream's provider
    /// closure at construction, before any engine exists.
    @MainActor
    private final class __EngineBox {
        var engine: ASREngine?
    }
}


// --------------------------------------------------------------------------------------
// TheStageFlutterPlugin + ASR node engine
// --------------------------------------------------------------------------------------
extension TheStageFlutterPlugin {

    func __handle_asr_engine_start(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let engine = __asr_node_engine else {
            result(nil)
            return
        }
        let dict = call.arguments as? [String: Any] ?? [:]
        Task { @MainActor in
            do {
                try await engine.start(dict)
                result(nil)
            } catch {
                result(FlutterError(
                    code: "THESTAGE_ASR_ENGINE_ERROR",
                    message: error.localizedDescription,
                    details: nil
                ))
            }
        }
    }

    func __handle_asr_engine_stop(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let engine = __asr_node_engine else {
            result(nil)
            return
        }
        Task { @MainActor in
            await engine.stop()
            result(nil)
        }
    }
}
