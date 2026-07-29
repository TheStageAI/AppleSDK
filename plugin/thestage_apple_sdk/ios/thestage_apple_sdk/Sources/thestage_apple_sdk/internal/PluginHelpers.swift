@preconcurrency import Flutter
import Foundation
import TheStageCore
import os

// --------------------------------------------------------------------------------------
// Encoding
// --------------------------------------------------------------------------------------
func __encode<T: Encodable>(
    _ value: T
) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    let json = try JSONSerialization.jsonObject(with: data)
    return json as? [String: Any] ?? [:]
}

func __encode_value<T: Encodable>(
    _ value: T
) throws -> Any {
    let data = try JSONEncoder().encode(value)
    return try JSONSerialization.jsonObject(with: data)
}

func __normalize(_ value: Any) -> Any {
    if let typed = value as? FlutterStandardTypedData {
        return typed.data
    }
    if let dict = value as? [String: Any] {
        var out: [String: Any] = [:]
        out.reserveCapacity(dict.count)
        for (k, v) in dict { out[k] = __normalize(v) }
        return out
    }
    if let list = value as? [Any] {
        return list.map { __normalize($0) }
    }
    return value
}

// --------------------------------------------------------------------------------------
// Argument Parsing
// --------------------------------------------------------------------------------------
func __parse_turn_start_mode(_ value: Any?) -> TurnStartMode? {
    guard let raw = value as? String else { return nil }
    switch raw {
    case "vad":                        return .vad
    case "vad_wake_word":              return .vad_wake_word
    case "vad_speaker_id_wake_word":   return .vad_speaker_id_wake_word
    default:                           return nil
    }
}

func __parse_turn_end_mode(_ value: Any?) -> TurnEndMode? {
    guard let raw = value as? String else { return nil }
    switch raw {
    case "none": return .none
    case "vad":  return .vad
    case "dnn":  return .dnn
    default:     return nil
    }
}

func __parse_interrupt_mode(_ value: Any?) -> InterruptMode? {
    guard let raw = value as? String else { return nil }
    switch raw {
    case "none":                       return .none
    case "vad", "speech_only":         return .vad
    case "vad_wake_word", "wake_word": return .vad_wake_word
    case "vad_speaker_id":             return .vad_speaker_id
    case "vad_speaker_id_wake_word":   return .vad_speaker_id_wake_word
    default:                           return nil
    }
}

func __parse_agent_states(_ value: Any?) -> [TheStageAgentState] {
    guard let raw = value as? [String] else { return [] }
    return raw.compactMap { TheStageAgentState(rawValue: $0) }
}

func __parse_embedding(_ value: Any?) -> [Double]? {
    if value is NSNull { return nil }
    guard let raw = value as? [Any] else { return nil }
    let parsed = raw.compactMap { element -> Double? in
        if let n = element as? Double { return n }
        if let n = element as? NSNumber { return n.doubleValue }
        return nil
    }
    return parsed.isEmpty ? nil : parsed
}

func __parse_devices(
    _ value: Any?
) -> [String: String]? {
    guard let raw = value as? [String: Any]
    else { return nil }
    var parsed: [String: String] = [:]
    for (k, v) in raw {
        if let s = v as? String { parsed[k] = s }
    }
    return parsed.isEmpty ? nil : parsed
}

func __parse_tts_stream_config(
    _ payload: [String: Any]?
) -> TTSStreamConfig {
    var sc = TTSStreamConfig()
    guard let payload else { return sc }
    if let v = payload["frames_per_chunk"] as? Int {
        sc.frames_per_chunk = v
    }
    if let raw = payload["first_frames_per_chunk"] {
        if let v = raw as? Int {
            sc.first_frames_per_chunk = v
        } else if raw is NSNull {
            sc.first_frames_per_chunk = nil
        }
    }
    if let v = payload["lookforward"] as? Int {
        sc.lookforward = v
    }
    if let v = payload["lookback"] as? Int {
        sc.lookback = v
    }
    if let v = payload["overlap_frames"] as? Int {
        sc.overlap_frames = v
    }
    return sc
}

func __parse_tts_generation_config(
    _ payload: [String: Any]
) -> TTSGenerationConfig {
    var c = TTSGenerationConfig()
    if let v = payload["temperature"] as? Double {
        c.temperature = v
    }
    if let v = payload["top_k"] as? Int {
        c.top_k = v
    }
    return c
}

// --------------------------------------------------------------------------------------
// Phonemizer Factory
// --------------------------------------------------------------------------------------
private let __phonemizer_logger = Logger(
    subsystem: "thestage_apple_sdk", category: "Phonemizer"
)

/// Build a phonemizer for phoneme-based TTS models (`neutts` / `neutts-nano`).
///
/// The plugin no longer bundles a phonemizer. Apps that need one register a
/// factory via `PhonemizerRegistry`. When nothing is registered we return
/// `nil`, and the SDK falls back to its built-in CoreML phonemizer (lower
/// quality) — so we log a one-time hint pointing at the espeak add-on.
/// Multilingual models never reach this path (they return `nil` early).
func __make_phonemizer(
    model_type: String?,
    config: [String: Any]?
) -> Phonemizer? {
    guard let mt = model_type else { return nil }
    let normalized = mt.lowercased()
        .replacingOccurrences(of: "_", with: "-")
    guard normalized == "neutts"
            || normalized == "neutts-nano"
            || normalized == "neu-tts"
    else { return nil }
    let lang = config?["language"] as? String ?? "en-us"
    if let phonemizer = PhonemizerRegistry.make(language: lang) {
        return phonemizer
    }
    __phonemizer_logger.warning(
        """
        No Phonemizer registered for \(normalized, privacy: .public); \
        falling back to the SDK's built-in CoreML phonemizer (lower quality). \
        For best nano quality, register one via PhonemizerRegistry.register \
        (see extras/espeak).
        """
    )
    return nil
}

// --------------------------------------------------------------------------------------
// Error Reporting
// --------------------------------------------------------------------------------------
func __fail(
    _ result: @escaping FlutterResult,
    msg: String
) {
    result(FlutterError(
        code: "THESTAGE_SDK_ERROR",
        message: msg,
        details: nil
    ))
}

func __fail(
    _ result: @escaping FlutterResult,
    error: Error
) {
    result(FlutterError(
        code: "THESTAGE_SDK_ERROR",
        message: __sanitize_error(error),
        details: nil
    ))
}

func __sanitize_error(_ error: Error) -> String {
    // Keep the operational reason (e.g. which CoreML function failed);
    // strip absolute paths so release builds don't leak device layout.
    TheStageLog.redact_error_text(String(describing: error))
}
