import Foundation
import TheStageSDK


// --------------------------------------------------------------------------------------
// BridgeCodec
// --------------------------------------------------------------------------------------
/// SDK values as JSON objects and back. Keys are the SDK's own field names,
/// so a binding's types read like the Swift documentation. A config decoded
/// from a dictionary starts from the model's defaults and overrides only the
/// keys the caller sent.
enum BridgeCodec {

    // LLM
    // ----------------------------------------------------------------------------------
    static func encode(_ config: LLMGenerationConfig) -> [String: Any] {
        var out: [String: Any] = [
            "max_new_tokens": config.max_new_tokens,
            "min_new_tokens": config.min_new_tokens,
            "temperature": Double(config.sampling.temperature),
            "top_k": config.sampling.top_k,
            "top_p": Double(config.sampling.top_p),
            "min_p": Double(config.sampling.min_p),
            "repetition_penalty": Double(config.sampling.repetition_penalty),
            "enable_thinking": config.enable_thinking,
            "stop_sequences": config.stop_sequences,
        ]
        if let seed = config.seed { out["seed"] = seed }
        if let speculative = config.speculative_decoding {
            out["speculative_decoding"] = speculative
        }
        return out
    }

    static func llm_config(
        _ dict: [String: Any], base: LLMGenerationConfig
    ) -> LLMGenerationConfig {
        var config = base
        if let v = (dict["max_new_tokens"] as? NSNumber)?.intValue {
            config.max_new_tokens = v
        }
        if let v = (dict["min_new_tokens"] as? NSNumber)?.intValue {
            config.min_new_tokens = v
        }
        if let v = (dict["temperature"] as? NSNumber)?.floatValue {
            config.sampling.temperature = v
        }
        if let v = (dict["top_k"] as? NSNumber)?.intValue { config.sampling.top_k = v }
        if let v = (dict["top_p"] as? NSNumber)?.floatValue { config.sampling.top_p = v }
        if let v = (dict["min_p"] as? NSNumber)?.floatValue { config.sampling.min_p = v }
        if let v = (dict["repetition_penalty"] as? NSNumber)?.floatValue {
            config.sampling.repetition_penalty = v
        }
        if let v = (dict["seed"] as? NSNumber)?.uint64Value { config.seed = v }
        if let v = (dict["enable_thinking"] as? NSNumber)?.boolValue {
            config.enable_thinking = v
        }
        if let v = dict["stop_sequences"] as? [String] { config.stop_sequences = v }
        if let v = (dict["speculative_decoding"] as? NSNumber)?.boolValue {
            config.speculative_decoding = v
        }
        return config
    }

    static func encode(_ chunk: LLMStreamChunk) -> [String: Any] {
        var out: [String: Any] = [
            "text": chunk.text, "token_index": chunk.token_index,
            "is_final": chunk.is_final,
        ]
        if chunk.is_final {
            out["time_to_first_token"] = chunk.time_to_first_token
            if let v = chunk.prompt_tokens { out["prompt_tokens"] = v }
            if let v = chunk.generated_tokens { out["generated_tokens"] = v }
            if let v = chunk.tokens_per_second { out["tokens_per_second"] = v }
            if let v = chunk.total_seconds { out["total_seconds"] = v }
            if let v = chunk.stop_reason { out["stop_reason"] = v }
        }
        return out
    }

    /// The event's case name and payload.
    static func encode(_ event: LLMStreamEvent) -> (String, [String: Any]) {
        switch event {
        case .text_delta(let text): return ("text_delta", ["text": text])
        case .thinking_delta(let text): return ("thinking_delta", ["text": text])
        case .tool_call(let call):
            return (
                "tool_call",
                ["name": call.name, "arguments": __json_safe(call.arguments)]
            )
        case .tool_round(let raw): return ("tool_round", ["assistant_raw": raw])
        case .tool_result(let name, let content):
            return ("tool_result", ["name": name, "content": content])
        case .final(let stop, let prompt, let generated, let tps, let total, let raw, _):
            var out: [String: Any] = [:]
            if let stop { out["stop_reason"] = stop }
            if let prompt { out["prompt_tokens"] = prompt }
            if let generated { out["generated_tokens"] = generated }
            if let tps { out["tokens_per_second"] = tps }
            if let total { out["total_seconds"] = total }
            if let raw { out["raw_text"] = raw }
            return ("final", out)
        @unknown default:
            return ("unknown", [:])
        }
    }

    static func encode(_ message: ChatMessage) -> [String: Any] {
        var text = ""
        var parts: [[String: Any]] = []
        for part in message.parts {
            switch part {
            case .TEXT(let t):
                text += t
                parts.append(["type": "text", "text": t])
            case .TOOL_CALL(let call):
                parts.append([
                    "type": "tool_call", "name": call.name,
                    "arguments": __json_safe(call.arguments),
                ])
            case .TOOL_RESULT(let name, let content):
                parts.append(["type": "tool_result", "name": name, "content": content])
            case .IMAGE: parts.append(["type": "image"])
            case .INPUT_AUDIO: parts.append(["type": "audio"])
            @unknown default: parts.append(["type": "unknown"])
            }
        }
        var out: [String: Any] = [
            "role": message.role.rawValue.lowercased(), "text": text, "parts": parts,
        ]
        if let name = message.name { out["name"] = name }
        return out
    }

    /// `[{role, content, name?}]` (roles `system`, `user`, `assistant`, `tool`). An
    /// assistant turn that called tools carries the model's own text for the call.
    static func chat_messages(_ items: [[String: Any]]) throws -> [ChatMessage] {
        try items.map { item in
            let raw = item["role"] as? String ?? ""
            guard let role = ChatRole(rawValue: raw.uppercased()) else {
                throw BridgeError.invalid_param(
                    "messages.role", "\(raw) is not system, user, assistant or tool")
            }
            let content = item["content"] as? String ?? ""
            let name = item["name"] as? String
            if role == .TOOL { return .tool(name: name ?? "tool", content: content) }
            return ChatMessage(role: role, parts: [.TEXT(content)], name: name)
        }
    }

    /// `[{name, description, parameters}]` (JSON Schema parameters). No handler:
    /// the caller runs the tool and sends the result back as a `tool` message.
    static func tools(_ items: [[String: Any]]) throws -> [Tool] {
        try items.map { item in
            guard let name = item["name"] as? String else {
                throw BridgeError.missing_param("tools.name")
            }
            return Tool(
                name: name, description: item["description"] as? String ?? "",
                parameters: item["parameters"] as? [String: Any] ?? [:])
        }
    }

    // ASR
    // ----------------------------------------------------------------------------------
    static func encode(_ word: ASRWord) -> [String: Any] {
        var out: [String: Any] = [
            "text": word.text, "t0": word.t0, "t1": word.t1, "is_final": word.is_final,
        ]
        if let s = word.speaker_id { out["speaker_id"] = s }
        if let c = word.confidence { out["confidence"] = c }
        return out
    }

    static func encode(_ result: ASRResult) -> [String: Any] {
        var out: [String: Any] = [
            "text": result.text, "words": (result.words ?? []).map(encode),
        ]
        if let language = result.language { out["language"] = language }
        return out
    }

    static func encode(_ turn: ASRTurn) -> [String: Any] {
        var out: [String: Any] = [
            "turn_order": turn.turn_order, "transcript": turn.transcript,
            "utterance": turn.utterance, "committed": turn.committed,
            "hypothesis": turn.hypothesis, "end_of_turn": turn.end_of_turn,
            "turn_is_formatted": turn.turn_is_formatted,
            "words": turn.words.map(encode),
            "speakers": turn.speakers.map(encode),
            "speaker_revision": turn.speaker_revision,
        ]
        if let language = turn.language { out["language"] = language }
        if let confidence = turn.end_of_turn_confidence {
            out["end_of_turn_confidence"] = confidence
        }
        if let speaker = turn.speaker_id { out["speaker_id"] = speaker }
        return out
    }

    static func encode(_ speaker: ASRSpeaker) -> [String: Any] {
        var out: [String: Any] = [
            "id": speaker.id, "identity_status": speaker.identity_status.rawValue,
            "speech_seconds": speaker.speech_seconds, "revision": speaker.revision,
        ]
        if let name = speaker.name { out["name"] = name }
        if let identity = speaker.identity_id { out["identity_id"] = identity }
        if let score = speaker.identity_score { out["identity_score"] = score }
        if let embedding = speaker.embedding { out["embedding"] = encode(embedding) }
        return out
    }

    // Speakers
    // ----------------------------------------------------------------------------------
    /// The SDK's own `Codable` form, so a file a client writes decodes in Swift.
    static func encode(_ vector: SpeakerEmbeddingVector) -> [String: Any] {
        var out: [String: Any] = [
            "values": vector.values.map(Double.init),
            "embedding_space_id": vector.embedding_space_id,
        ]
        if let seconds = vector.speech_seconds { out["speech_seconds"] = seconds }
        return out
    }

    static func encode(_ profile: SpeakerProfile) -> [String: Any] {
        ["id": profile.id, "name": profile.name, "embeddings": profile.embeddings.map(encode)]
    }

    /// `[SpeakerProfile]` from a JSON list (absent: none).
    static func profiles(_ value: Any?) throws -> [SpeakerProfile] {
        guard let value, !(value is NSNull) else { return [] }
        guard JSONSerialization.isValidJSONObject(value), value is [Any] else {
            throw BridgeError.invalid_param("enrolled", "a list of speaker profiles")
        }
        do {
            return try JSONDecoder().decode(
                [SpeakerProfile].self, from: JSONSerialization.data(withJSONObject: value))
        } catch {
            throw BridgeError.invalid_param(
                "enrolled", "not a speaker profile list (\(error.localizedDescription))")
        }
    }

    /// `SpeakerIDConfig` from `identity`: `enrolled`, the scalar thresholds that are
    /// set, and each rule (`voice_change`, `long_turn_merge`, `evidence`) as a dict
    /// (absent = off, `{}` = the SDK's defaults for it, keys override). `ASRSpeakerConfig`
    /// validates the result when the route builds it.
    static func speaker_identity(_ dict: [String: Any]) throws -> SpeakerIDConfig {
        var config = SpeakerIDConfig(enrolled: try profiles(dict["enrolled"]))
        if let v = double(dict, "identity_threshold") { config.identity_threshold = v }
        if let v = double(dict, "identity_neg_threshold") { config.identity_neg_threshold = v }
        if let v = double(dict, "identity_margin") { config.identity_margin = v }
        if let v = double(dict, "min_identity_speech_s") { config.min_identity_speech_s = v }
        if let v = double(dict, "update_speech_s") { config.update_speech_s = v }
        if let v = double(dict, "rejoin_threshold") { config.rejoin_threshold = v }
        if let v = double(dict, "split_rejoin_s") { config.split_rejoin_s = v }
        if let v = double(dict, "label_reseed_s") { config.label_reseed_s = v }
        if let v = bool(dict, "turn_identity") { config.turn_identity = v }
        if let rule = try rule(dict, "voice_change") {
            var change = SpeakerVoiceChangeConfig()
            if let v = double(rule, "piece_s") { change.piece_s = v }
            if let v = double(rule, "hop_s") { change.hop_s = v }
            if let v = double(rule, "voice_delay_s") { change.voice_delay_s = v }
            if let v = double(rule, "threshold") { change.threshold = v }
            if let v = double(rule, "run_s") { change.run_s = v }
            config.voice_change = change
        }
        if let rule = try rule(dict, "long_turn_merge") {
            var merge = SpeakerLongTurnMergeConfig()
            if let v = double(rule, "min_turn_s") { merge.min_turn_s = v }
            if let v = double(rule, "threshold") { merge.threshold = v }
            config.long_turn_merge = merge
        }
        if let rule = try rule(dict, "evidence") {
            var evidence = SpeakerEvidenceConfig()
            if let v = bool(rule, "turn_evidence") { evidence.turn_evidence = v }
            if let v = bool(rule, "turn_born") { evidence.turn_born = v }
            if let v = double(rule, "new_speaker_min_turn_s") { evidence.new_speaker_min_turn_s = v }
            if let v = bool(rule, "skip_overlap") { evidence.skip_overlap = v }
            config.evidence = evidence
        }
        return config
    }

    /// A rule's dict under `key`: `nil` when absent or JSON null (the rule is off).
    private static func rule(_ dict: [String: Any], _ key: String) throws -> [String: Any]? {
        guard let value = dict[key], !(value is NSNull) else { return nil }
        guard let rule = value as? [String: Any] else {
            throw BridgeError.invalid_param("identity.\(key)", "an object of the rule's fields")
        }
        return rule
    }

    private static func double(_ dict: [String: Any], _ key: String) -> Double? {
        (dict[key] as? NSNumber)?.doubleValue
    }

    private static func bool(_ dict: [String: Any], _ key: String) -> Bool? {
        (dict[key] as? NSNumber)?.boolValue
    }

    static func asr_generation(_ dict: [String: Any]) -> ASRGenerationConfig {
        let timestamps: ASRTimestampMode =
            (dict["timestamps"] as? String)?.uppercased() == "NONE" ? .NONE : .WORD
        return ASRGenerationConfig(
            language: dict["language"] as? String ?? "auto", timestamps: timestamps)
    }

    // Audio
    // ----------------------------------------------------------------------------------
    /// `{aec, agc, mute_mic_during_playback, aec_warmup_ms, sample_rate_out}` over
    /// `base`. System and meeting capture run without a canceller (the tap's remote
    /// voices are content, not the app's playback), so another `aec` there is an error
    /// rather than a silent change.
    static func audio(
        _ dict: [String: Any], base: AudioEngineConfig, source: BridgeAudioSource
    ) throws -> AudioEngineConfig {
        var audio = base
        if let aec = dict["aec"] as? String {
            guard let method = AECMethod(rawValue: aec.uppercased()) else {
                throw BridgeError.invalid_param(
                    "aec", "\(aec) is not webrtc, vpio, neural or none")
            }
            if source.taps_system_output, method != .NONE {
                throw BridgeError.invalid_param(
                    "aec", "\(source.name) capture takes aec none")
            }
            audio.aec_method = method
        }
        if source.taps_system_output { audio.aec_method = .NONE }
        audio.voice_processing = audio.aec_method == .VPIO
        if let v = (dict["agc"] as? NSNumber)?.boolValue { audio.agc = v }
        if let v = (dict["mute_mic_during_playback"] as? NSNumber)?.boolValue {
            audio.mute_mic_during_playback = v
        }
        if let v = (dict["aec_warmup_ms"] as? NSNumber)?.intValue {
            audio.aec_warmup_ms = v
        }
        if let v = (dict["sample_rate_out"] as? NSNumber)?.doubleValue {
            audio.sample_rate_out = v
        }
        return audio
    }

    // TTS
    // ----------------------------------------------------------------------------------
    static func tts_config(_ dict: [String: Any]) -> TTSGenerationConfig {
        var config = TTSGenerationConfig()
        if let v = (dict["temperature"] as? NSNumber)?.doubleValue {
            config.temperature = v
        }
        if let v = (dict["top_k"] as? NSNumber)?.intValue { config.top_k = v }
        if let v = (dict["seed"] as? NSNumber)?.uint64Value { config.seed = v }
        if let v = (dict["sample_rate_out"] as? NSNumber)?.intValue {
            config.sample_rate_out = v
        }
        return config
    }

    // Private Methods
    // ----------------------------------------------------------------------------------
    /// Tool arguments come from decoded JSON; anything else becomes its
    /// description so `JSONSerialization` never throws on the frame.
    private static func __json_safe(_ value: [String: Any]) -> [String: Any] {
        JSONSerialization.isValidJSONObject(value) ? value : value.mapValues { "\($0)" }
    }
}
