import Foundation

// --------------------------------------------------------------------------------------
// MethodChannels
// --------------------------------------------------------------------------------------
enum MethodChannels {
    static let main = "thestage_apple_sdk"
    static let progress = "thestage_apple_sdk/progress"
    static let ttsStream = "thestage_apple_sdk/tts_stream"
    static let voiceAgentEvents = "thestage_apple_sdk/voice_agent_events"
    static let voiceAgentLLMDeltas =
        "thestage_apple_sdk/voice_agent_llm_deltas"
    static let voiceAgentTranscripts =
        "thestage_apple_sdk/voice_agent_transcripts"
    static let voiceAgentVADProbabilities =
        "thestage_apple_sdk/voice_agent_vad_probabilities"
}

// --------------------------------------------------------------------------------------
// MethodRoute
// --------------------------------------------------------------------------------------
enum MethodRoute {
    static let initialize = "initialize"
    static let startModel = "start_model"
    static let stopModel = "stop_model"

    static let listComponents = "list_components"
    static let loadComponents = "load_components"
    static let unloadComponents = "unload_components"
    static let bundledEnginePath = "get_bundled_engine_path"

    static let memoryFootprint = "memory_footprint"

    static let infer = "infer"
    static let startStream = "start_stream"
    static let send = "send"
    static let finishStream = "finish_stream"
    static let stopStream = "stop_stream"

    static let audioStart = "audio_start"
    static let audioEnqueue = "audio_enqueue"
    static let audioPause = "audio_pause"
    static let audioResume = "audio_resume"
    static let audioDrain = "audio_drain"
    static let audioStop = "audio_stop"

    static let voiceAgentStart = "voice_agent.start"
    static let voiceAgentStop = "voice_agent.stop"
    static let voiceAgentInterrupt = "voice_agent.interrupt"
    static let voiceAgentSay = "voice_agent.say"
    static let voiceAgentSetVoice = "voice_agent.set_voice"
    static let voiceAgentClearHistory = "voice_agent.clear_history"
    static let voiceAgentUpdateInterruptConfig =
        "voice_agent.update_interrupt_config"
}
