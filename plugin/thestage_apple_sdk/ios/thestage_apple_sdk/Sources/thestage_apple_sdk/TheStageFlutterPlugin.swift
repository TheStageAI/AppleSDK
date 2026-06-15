@preconcurrency import Flutter
import Foundation
import TheStageCore

// --------------------------------------------------------------------------------------
// TheStageFlutterPlugin
// --------------------------------------------------------------------------------------
@MainActor
public final class TheStageFlutterPlugin: NSObject, FlutterPlugin,
    FlutterStreamHandler
{
    // ----------------------------------------------------------------------------------
    // Private Attributes
    // ----------------------------------------------------------------------------------
    var __progress_sink: FlutterEventSink?
    var __stream_handler: TTSStreamHandler?
    var __voice_agent_handler: VoiceAgentStateStream?
    var __voice_agent_llm_deltas: VoiceAgentBroadcastStream?
    var __voice_agent_transcripts: VoiceAgentBroadcastStream?
    var __voice_agent_vad_probs: VoiceAgentBroadcastStream?
    var __audio_players: [String: TheStageCore.AudioStreamPlayer] = [:]

    // ----------------------------------------------------------------------------------
    // Registration
    // ----------------------------------------------------------------------------------
    public static func register(
        with registrar: FlutterPluginRegistrar
    ) {
        let channel = FlutterMethodChannel(
            name: MethodChannels.main,
            binaryMessenger: registrar.messenger()
        )
        let instance = TheStageFlutterPlugin()
        registrar.addMethodCallDelegate(
            instance, channel: channel
        )

        let progress = FlutterEventChannel(
            name: MethodChannels.progress,
            binaryMessenger: registrar.messenger()
        )
        progress.setStreamHandler(instance)

        let stream = FlutterEventChannel(
            name: MethodChannels.ttsStream,
            binaryMessenger: registrar.messenger()
        )
        let handler = TTSStreamHandler()
        stream.setStreamHandler(handler)
        instance.__stream_handler = handler

        let voiceAgentEvents = FlutterEventChannel(
            name: MethodChannels.voiceAgentEvents,
            binaryMessenger: registrar.messenger()
        )
        let vaHandler = VoiceAgentStateStream()
        voiceAgentEvents.setStreamHandler(vaHandler)
        instance.__voice_agent_handler = vaHandler

        let llmDeltas = FlutterEventChannel(
            name: MethodChannels.voiceAgentLLMDeltas,
            binaryMessenger: registrar.messenger()
        )
        let llmDeltasHandler = VoiceAgentBroadcastStream.string(
            agent_provider: { [weak vaHandler] in vaHandler?.agent },
            port: { agent in agent.llm_deltas }
        )
        llmDeltas.setStreamHandler(llmDeltasHandler)
        vaHandler.register_tap(llmDeltasHandler)
        instance.__voice_agent_llm_deltas = llmDeltasHandler

        let transcripts = FlutterEventChannel(
            name: MethodChannels.voiceAgentTranscripts,
            binaryMessenger: registrar.messenger()
        )
        let transcriptsHandler = VoiceAgentBroadcastStream.string(
            agent_provider: { [weak vaHandler] in vaHandler?.agent },
            port: { agent in agent.transcripts }
        )
        transcripts.setStreamHandler(transcriptsHandler)
        vaHandler.register_tap(transcriptsHandler)
        instance.__voice_agent_transcripts = transcriptsHandler

        let vadProbs = FlutterEventChannel(
            name: MethodChannels.voiceAgentVADProbabilities,
            binaryMessenger: registrar.messenger()
        )
        let vadProbsHandler = VoiceAgentBroadcastStream.double(
            agent_provider: { [weak vaHandler] in vaHandler?.agent },
            port: { agent in agent.vad_probabilities }
        )
        vadProbs.setStreamHandler(vadProbsHandler)
        vaHandler.register_tap(vadProbsHandler)
        instance.__voice_agent_vad_probs = vadProbsHandler
    }

    // ----------------------------------------------------------------------------------
    // Progress EventChannel
    // ----------------------------------------------------------------------------------
    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        __progress_sink = events
        return nil
    }

    public func onCancel(
        withArguments arguments: Any?
    ) -> FlutterError? {
        __progress_sink = nil
        return nil
    }

    // ----------------------------------------------------------------------------------
    // Method Dispatch
    // ----------------------------------------------------------------------------------
    public func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        switch call.method {
        case MethodRoute.initialize:
            __handle_initialize(call, result: result)
        case MethodRoute.startModel:
            __handle_start_model(call, result: result)
        case MethodRoute.stopModel:
            __handle_stop_model(call, result: result)

        case MethodRoute.listComponents:
            __handle_list_components(call, result: result)
        case MethodRoute.loadComponents:
            __handle_load_components(call, result: result)
        case MethodRoute.unloadComponents:
            __handle_unload_components(call, result: result)
        case MethodRoute.bundledEnginePath:
            __handle_bundled_engine_path(call, result: result)
        case MethodRoute.memoryFootprint:
            __handle_memory_footprint(call, result: result)

        case MethodRoute.infer:
            __handle_infer(call, result: result)
        case MethodRoute.startStream:
            __handle_start_stream(call, result: result)
        case MethodRoute.send:
            __handle_send_stream(call, result: result)
        case MethodRoute.finishStream:
            __handle_finish_stream(call, result: result)
        case MethodRoute.stopStream:
            __handle_stop_stream(call, result: result)

        case MethodRoute.audioStart:
            __handle_audio_start(call, result: result)
        case MethodRoute.audioEnqueue:
            __handle_audio_enqueue(call, result: result)
        case MethodRoute.audioPause:
            __handle_audio_pause(call, result: result)
        case MethodRoute.audioResume:
            __handle_audio_resume(call, result: result)
        case MethodRoute.audioDrain:
            __handle_audio_drain(call, result: result)
        case MethodRoute.audioStop:
            __handle_audio_stop(call, result: result)

        case MethodRoute.voiceAgentStart:
            __handle_voice_agent_start(call, result: result)
        case MethodRoute.voiceAgentStop:
            __handle_voice_agent_stop(call, result: result)
        case MethodRoute.voiceAgentInterrupt:
            __handle_voice_agent_interrupt(call, result: result)
        case MethodRoute.voiceAgentSay:
            __handle_voice_agent_say(call, result: result)
        case MethodRoute.voiceAgentSetVoice:
            __handle_voice_agent_set_voice(call, result: result)
        case MethodRoute.voiceAgentClearHistory:
            __handle_voice_agent_clear_history(call, result: result)
        case MethodRoute.voiceAgentUpdateInterruptConfig:
            __handle_voice_agent_update_interrupt_config(
                call, result: result
            )

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
