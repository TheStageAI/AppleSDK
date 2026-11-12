import Foundation
import TheStageSDK


// --------------------------------------------------------------------------------------
// ASRRoutes
// --------------------------------------------------------------------------------------
/// `asr.load`, `asr.infer`, `asr.infer_stream` (16 kHz float32 PCM as the call's
/// body). With a `vad`, a file is cut in silence and silent windows are skipped
/// (`ASREngine(pipeline:vad:)`, the SDK's batch path).
enum ASRRoutes {
    static func register(in core: BridgeCore) {
        core.register("asr.load") { call in
            let path = try call.string("engines_path")
            let name = call.string("model_name", default: path) ?? path
            let device = call.string("device", default: "npu") ?? "npu"
            let pipeline = try await TheStageAI.shared.start_model(
                ASRPipeline.self, model_name: name, engines_path: path, device: device)
            var vad: SileroVAD?
            if let repo = call.string("vad", default: nil) {
                let vad_path = try await TheStageAI.shared.prefetch_engines(
                    repo_id: repo, model_type: "thestage_vad")
                vad = try SileroVAD(engines_path: vad_path, device: device)
            }
            let engine = ASREngine(pipeline: pipeline, vad: vad)
            return .init([
                "handle": call.core.keep(engine, prefix: "asr"), "model_name": name,
                "sample_rate": pipeline.sample_rate,
            ])
        }
        core.register("asr.infer") { call in
            let engine = try call.object("asr", as: ASREngine.self)
            let result = try await engine.infer(
                audio: call.pcm, config: BridgeCodec.asr_generation(call.dict("config")))
            return .init(BridgeCodec.encode(result))
        }
        /// `partial` events (the transcript so far; its text only grows), then
        /// one `final` (what `asr.infer` returns), then `end`.
        core.register("asr.infer_stream") { call in
            let engine = try call.object("asr", as: ASREngine.self)
            let results = engine.infer_stream(
                audio: call.pcm, config: BridgeCodec.asr_generation(call.dict("config")))
            let core = call.core
            let stream = core.keep(StreamToken(), prefix: "stream")
            return .init(
                ["stream": stream],
                after: {
                    Task {
                        // The last element is the final result.
                        var held: ASRResult?
                        do {
                            for try await result in results {
                                if let held {
                                    core.event(
                                        stream, "partial", BridgeCodec.encode(held))
                                }
                                held = result
                            }
                            if let held {
                                core.event(stream, "final", BridgeCodec.encode(held))
                            }
                            core.end(stream)
                        } catch {
                            core.end(stream, error: error)
                        }
                        core.release(stream)
                    }
                })
        }
    }
}


// --------------------------------------------------------------------------------------
// MediaRoutes
// --------------------------------------------------------------------------------------
/// `audio.decode`: an encoded file (WAV, M4A/AAC, MP3, FLAC, CAF, AIFF; anything
/// AVAudioFile reads) as mono float32 at `sample_rate` (16 kHz by default).
enum MediaRoutes {
    static func register(in core: BridgeCore) {
        core.register("audio.decode") { call in
            let rate = call.int("sample_rate") ?? 16_000
            let ext = call.string("format", default: "audio") ?? "audio"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("thestage-\(UUID().uuidString).\(ext)")
            try call.body.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let samples: [Float]
            do {
                samples = try AudioIO.load_wav(url: url, target_sample_rate: rate)
            } catch {
                throw BridgeError.invalid_param(
                    "audio", "not a readable audio file (\(error.localizedDescription))")
            }
            return .init(
                ["sample_rate": rate, "duration": Double(samples.count) / Double(rate)],
                body: BridgeFrame.pcm_body(samples))
        }
    }
}


// --------------------------------------------------------------------------------------
// TTSRoutes
// --------------------------------------------------------------------------------------
/// `tts.load`, `tts.infer`, `tts.open_stream` / `tts.send` / `tts.close` /
/// `tts.cancel`. Audio comes back as float32 bodies at `sample_rate`.
enum TTSRoutes {
    static func register(in core: BridgeCore) {
        core.register("tts.load") { call in
            let path = try call.string("engines_path")
            let name = call.string("model_name", default: path) ?? path
            let tts = try await TheStageAI.shared.start_model(
                TSTTSPipeline.self, model_name: name, engines_path: path,
                device: call.string("device", default: "npu") ?? "npu")
            if let voice = call.string("voice_id", default: nil) {
                try tts.set_voice(
                    voice_id: voice, language: call.string("language", default: nil))
            }
            return .init([
                "handle": call.core.keep(tts, prefix: "tts"), "model_name": name,
                "sample_rate": tts.sample_rate,
            ])
        }
        core.register("tts.set_voice") { call in
            let tts = try call.object("tts", as: TSTTSPipeline.self)
            try tts.set_voice(
                voice_id: try call.string("voice_id"),
                language: call.string("language", default: nil))
            return .init()
        }
        core.register("tts.infer") { call in
            let tts = try call.object("tts", as: TSTTSPipeline.self)
            let text = try call.string("text")
            let config = BridgeCodec.tts_config(call.dict("config"))
            let result = await Task.detached { tts.infer(text: text, config: config) }
                .value
            return .init(
                [
                    "sample_rate": result.sample_rate, "duration": result.duration,
                    "rtf": result.rtf,
                ],
                body: BridgeFrame.pcm_body(result.samples))
        }
        /// `tts.open_stream()`: `audio` events (float32 body) as speech is
        /// made, `end` once `tts.close` has drained it.
        core.register("tts.open_stream") { call in
            let tts = try call.object("tts", as: TSTTSPipeline.self)
            let speech = tts.open_stream(BridgeCodec.tts_config(call.dict("config")))
            let core = call.core
            let stream = core.keep(speech, prefix: "tts_stream")
            return .init(
                ["stream": stream, "sample_rate": speech.sample_rate],
                after: {
                    Task {
                        for await chunk in speech.output {
                            guard let pcm = chunk.audio, !pcm.isEmpty else { continue }
                            core.event(
                                stream, "audio",
                                ["sample_rate": chunk.sample_rate ?? speech.sample_rate],
                                body: BridgeFrame.pcm_body(pcm))
                        }
                        core.end(stream)
                        core.release(stream)
                    }
                })
        }
        core.register("tts.send") { call in
            try call.object("stream", as: TTSStream.self).send(try call.string("text"))
            return .init()
        }
        core.register("tts.close") { call in
            try call.object("stream", as: TTSStream.self).close()
            return .init()
        }
        core.register("tts.cancel") { call in
            try call.object("stream", as: TTSStream.self).cancel()
            return .init()
        }
    }
}


// --------------------------------------------------------------------------------------
// ASREngineRoutes
// --------------------------------------------------------------------------------------
/// `asr_engine.create`, `asr_engine.turns`, `asr_engine.start`,
/// `asr_engine.push`, `asr_engine.stop`, `asr_engine.update_enrolled_speakers`. The engine captures in the host
/// (`audio.source`: microphone, system, meeting) or takes pushed PCM at any
/// rate (`push`).
enum ASREngineRoutes {
    static func register(in core: BridgeCore) {
        core.register("asr_engine.create") { call in
            let (config, input) = try await EngineHandle.agent_config(call.params)
            let engine = ASREngine(config: config)
            return .init([
                "handle": call.core.keep(
                    EngineHandle(engine: engine, input: input), prefix: "asr_engine")
            ])
        }
        /// Cumulative `ASRTurn`s (`turn` events). Subscribe before `start`.
        core.register("asr_engine.turns") { call in
            let handle = try call.object("engine", as: EngineHandle.self)
            let turns = handle.engine.turns.recv()
            let core = call.core
            let stream = core.keep(StreamToken(), prefix: "stream")
            return .init(
                ["stream": stream],
                after: {
                    Task {
                        for await turn in turns {
                            core.event(stream, "turn", BridgeCodec.encode(turn))
                        }
                        core.end(stream)
                        core.release(stream)
                    }
                })
        }
        core.register("asr_engine.start") { call in
            try await call.object("engine", as: EngineHandle.self).engine.start()
            return .init()
        }
        core.register("asr_engine.push") { call in
            let handle = try call.object("engine", as: EngineHandle.self)
            guard let input = handle.input else {
                throw BridgeError.invalid_param(
                    "audio.source", "push needs an engine created with source push")
            }
            input.send(
                PCM(samples: call.pcm, sample_rate: call.int("sample_rate") ?? 16_000))
            return .init()
        }
        core.register("asr_engine.stop") { call in
            try await call.object("engine", as: EngineHandle.self).engine.stop()
            return .init()
        }
        /// `profiles`: the saved voices to name speakers by, from now on.
        core.register("asr_engine.update_enrolled_speakers") { call in
            let handle = try call.object("engine", as: EngineHandle.self)
            try await handle.engine.update_enrolled_speakers(
                BridgeCodec.profiles(call.params["profiles"]))
            return .init()
        }
    }
}


// --------------------------------------------------------------------------------------
// SpeakerIDRoutes
// --------------------------------------------------------------------------------------
/// `speaker_id.load`, `speaker_id.enroll`: a saved voice (`SpeakerProfile` JSON) from
/// a clean recording (16 kHz float32 PCM as the call's body).
enum SpeakerIDRoutes {
    static func register(in core: BridgeCore) {
        core.register("speaker_id.load") { call in
            let path = try call.string("engines_path")
            let identifier = try await SpeakerIDPipeline(engines_path: path)
            return .init([
                "handle": call.core.keep(identifier, prefix: "speaker_id"),
                "sample_rate": identifier.sample_rate,
                "embedding_space_id": identifier.embedding_space_id,
            ])
        }
        core.register("speaker_id.enroll") { call in
            let identifier = try call.object("speaker_id", as: SpeakerIDPipeline.self)
            let profile = try await identifier.enroll(
                audio: call.pcm, id: try call.string("id"), name: try call.string("name"))
            return .init(["profile": BridgeCodec.encode(profile)])
        }
    }
}


// --------------------------------------------------------------------------------------
// VoiceAgentRoutes
// --------------------------------------------------------------------------------------
/// `voice_agent.create`, `voice_agent.events`, `.start`, `.begin_listening`,
/// `.pause_listening`, `.stop`, `.say`, `.send_request`, `.interrupt`,
/// `.clear_history`, `.set_system_prompt`. The LLM is a model the client
/// loaded with `llm.load` (`llm_model` is its `model_name`); `tools` with
/// `callback` run in the client through the returned `tools` relay.
enum VoiceAgentRoutes {
    static func register(in core: BridgeCore) {
        core.register("voice_agent.create") { call in
            var (config, _) = try await EngineHandle.agent_config(call.params)
            if let tts = call.string("tts", default: nil) { config.tts = tts }
            if let voice = call.string("tts_voice", default: nil) {
                config.tts_voice = voice
            }
            let llm = try call.string("llm_model")
            let (relay, tools) = try ToolRelay.make(
                core: call.core, items: call.params["tools"] as? [[String: Any]] ?? [])
            config.llm = TSLocalLLMProvider(
                model_path: llm, tools: tools,
                system_prompt: call.string("system_prompt", default: nil)
            )
            let agent = TSVoiceAgent(config: config)
            let handle = call.core.keep(
                AgentHandle(agent: agent, relay: relay), prefix: "voice_agent")
            var result: [String: Any] = ["handle": handle]
            if let relay { result["tools"] = relay.handle }
            return .init(result)
        }
        /// `TSAgentEvent`s by kind (`state_changed`, `user_request_partial`,
        /// `user_request`, `response_delta`, `tool_started`, …).
        core.register("voice_agent.events") { call in
            let agent = try call.object("agent", as: AgentHandle.self).agent
            let core = call.core
            let stream = core.keep(StreamToken(), prefix: "stream")
            return .init(
                ["stream": stream],
                after: {
                    Task {
                        for await event in agent.events {
                            let data =
                                JSONSerialization.isValidJSONObject(event.data)
                                ? event.data : event.data.mapValues { "\($0)" }
                            core.event(stream, event.kind.rawValue, data)
                        }
                        core.end(stream)
                        core.release(stream)
                    }
                })
        }
        core.register("voice_agent.start") { call in
            try await call.object("agent", as: AgentHandle.self).agent.start()
            return .init()
        }
        core.register("voice_agent.begin_listening") { call in
            try await call.object("agent", as: AgentHandle.self).agent.begin_listening()
            return .init()
        }
        core.register("voice_agent.pause_listening") { call in
            try await call.object("agent", as: AgentHandle.self).agent.pause_listening()
            return .init()
        }
        core.register("voice_agent.stop") { call in
            try await call.object("agent", as: AgentHandle.self).agent.stop()
            return .init()
        }
        core.register("voice_agent.say") { call in
            try call.object("agent", as: AgentHandle.self).agent.say(
                try call.string("text"))
            return .init()
        }
        core.register("voice_agent.send_request") { call in
            try call.object("agent", as: AgentHandle.self).agent.send_request(
                try call.string("text"))
            return .init()
        }
        core.register("voice_agent.interrupt") { call in
            try call.object("agent", as: AgentHandle.self).agent.interrupt()
            return .init()
        }
        core.register("voice_agent.clear_history") { call in
            try await call.object("agent", as: AgentHandle.self).agent.clear_history()
            return .init()
        }
        core.register("voice_agent.set_system_prompt") { call in
            let agent = try call.object("agent", as: AgentHandle.self).agent
            await agent.set_system_prompt(try call.string("prompt"))
            return .init()
        }
    }
}


// --------------------------------------------------------------------------------------
// Handles
// --------------------------------------------------------------------------------------
/// An engine and, in push mode, the node its audio comes through.
final class EngineHandle: @unchecked Sendable {

    // Public Attributes
    // ----------------------------------------------------------------------------------
    let engine: ASREngine
    let input: PCMInputNode?

    // Constructor
    // ----------------------------------------------------------------------------------
    init(engine: ASREngine, input: PCMInputNode?) {
        self.engine = engine
        self.input = input
    }

    deinit {}

    // Public Methods
    // ----------------------------------------------------------------------------------
    /// `TSAgentConfig(vad:stt:turn_detector:)` and the fields a client sets, by their
    /// SDK names: `language`, `timestamps`, `turn_end_mode` (`vad`, `dnn`, `none`),
    /// `turn_eot_threshold`, `turn_pause_trigger_ms`, `asr_streaming_config`
    /// ({`algorithm`: wire name}), `speakers` (``speaker_config(_:)``) and `audio`
    /// (``BridgeAudioSource`` plus ``BridgeCodec/audio(_:base:source:)``). A field the
    /// client leaves out keeps the SDK default. The push node comes back with the
    /// config when the source is `push`.
    static func agent_config(
        _ params: [String: Any]
    ) async throws -> (TSAgentConfig, PCMInputNode?) {
        guard let stt = params["stt"] as? String else {
            throw BridgeError.missing_param("stt")
        }
        var config = TSAgentConfig(
            vad: params["vad"] as? String ?? "TheStageAI/silero-vad", stt: stt,
            turn_detector: params["turn_detector"] as? String)
        config.asr_generation = BridgeCodec.asr_generation(params)
        if let name = params["turn_end_mode"] as? String {
            guard let mode = TurnEndMode(rawValue: name) else {
                throw BridgeError.invalid_param("turn_end_mode", "vad, dnn or none")
            }
            config.turn_end_mode = mode
        }
        if let threshold = (params["turn_eot_threshold"] as? NSNumber)?.doubleValue {
            config.turn_eot_threshold = threshold
        }
        if let ms = (params["turn_pause_trigger_ms"] as? NSNumber)?.intValue {
            config.turn_pause_trigger_ms = ms
        }
        let streaming = params["asr_streaming_config"] as? [String: Any] ?? [:]
        if let name = streaming["algorithm"] as? String {
            guard let algorithm = ASRStreamingAlgorithm.decoding(name) else {
                throw BridgeError.invalid_param(
                    "asr_streaming_config.algorithm", "unknown algorithm \(name)")
            }
            config.asr_streaming_config.algorithm = algorithm
        }
        let audio = params["audio"] as? [String: Any] ?? [:]
        let source = try BridgeAudioSource(audio["source"] as? String)
        config.audio = try BridgeCodec.audio(audio, base: config.audio, source: source)
        let input = source == .PUSH ? PCMInputNode() : nil
        config.audio_node_factory = source.node_factory(push: input)
        if let speakers = params["speakers"] as? [String: Any] {
            config.speakers = try await speaker_config(speakers)
        }
        return (config, input)
    }

    /// `ASRSpeakerConfig` from `{diarization, identification, identity}`: repos default
    /// to the SDK's packs; `identification: null` turns identity off; `identity` is
    /// decoded by `BridgeCodec.speaker_identity` (saved voices, thresholds, rules).
    static func speaker_config(_ params: [String: Any]) async throws -> ASRSpeakerConfig {
        let diarizer = try await NemotronDiarizationPipeline(
            engines_path: params["diarization"] as? String
                ?? "TheStageAI/Nemotron-3-Diarization")
        let identifier: SpeakerIDPipeline? =
            params["identification"] is NSNull
            ? nil
            : try await SpeakerIDPipeline(
                engines_path: params["identification"] as? String
                    ?? "TheStageAI/speaker-id-v2")
        let identity = params["identity"] as? [String: Any] ?? [:]
        return ASRSpeakerConfig(
            diarization: diarizer, identification: identifier,
            identity: try BridgeCodec.speaker_identity(identity))
    }
}


// --------------------------------------------------------------------------------------
// BridgeAudioSource
// --------------------------------------------------------------------------------------
/// Where an engine's or agent's audio comes from (`audio.source`; on the wire
/// the lowercase case name).
enum BridgeAudioSource: String {
    /// The default input through the SDK's audio engine node (with its canceller).
    case MICROPHONE
    /// Everything the Mac plays (Core Audio process tap, macOS 14.2+).
    case SYSTEM
    /// System output and the microphone, mixed.
    case MEETING
    /// PCM the client sends with `asr_engine.push`.
    case PUSH

    // Constructor
    // ----------------------------------------------------------------------------------
    init(_ raw: String?) throws {
        guard let source = Self(rawValue: (raw ?? "microphone").uppercased())
        else {
            throw BridgeError.invalid_param(
                "audio.source", "\(raw ?? "") is not microphone, system, meeting or push")
        }
        self = source
    }

    // Public Attributes
    // ----------------------------------------------------------------------------------
    var name: String { rawValue.lowercased() }

    var taps_system_output: Bool { self == .SYSTEM || self == .MEETING }

    // Public Methods
    // ----------------------------------------------------------------------------------
    /// The node for this source; nil keeps the SDK's own microphone node.
    func node_factory(push input: PCMInputNode?) -> AgentAudioNodeFactory? {
        switch self {
        case .MICROPHONE:
            return nil

        case .PUSH:
            guard let input else { return nil }
            return { _ in input }

        case .SYSTEM, .MEETING:
            let mode: CoreAudioTapMode =
                self == .MEETING
                ? .SYSTEM_OUTPUT_AND_MICROPHONE : .SYSTEM_OUTPUT
            return { audio in CoreAudioTapNode(audio_config: audio, mode: mode) }
        }
    }
}

final class AgentHandle: @unchecked Sendable {

    // Public Attributes
    // ----------------------------------------------------------------------------------
    let agent: TSVoiceAgent
    let relay: ToolRelay?

    // Constructor
    // ----------------------------------------------------------------------------------
    init(agent: TSVoiceAgent, relay: ToolRelay? = nil) {
        self.agent = agent
        self.relay = relay
    }

    deinit { relay?.close() }
}
