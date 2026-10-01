import Foundation
import CryptoKit
import SwiftUI
import UIKit
#if canImport(TheStageSDK)
import TheStageSDK
#else
import TheStageCore
#endif

enum BundleSpeculation {
    /// Hash the actual installed artifacts, outside all measured intervals.
    /// Key material is excluded; published-at-build hashes are not a substitute.
    static func identity(_ root: URL) async throws -> [String: String] {
        try await Task.detached(priority: .utility) {
            guard let iterator = FileManager.default.enumerator(at: root,
                includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            else { throw CocoaError(.fileReadUnknown) }
            let files = try iterator.compactMap { value -> URL? in
                guard let url = value as? URL,
                    url.lastPathComponent != "qlip_key.bin",
                    try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
                else { return nil }
                return url
            }.sorted { $0.path < $1.path }
            var digest = SHA256()
            for file in files {
                let name = String(file.path.dropFirst(root.path.count + 1))
                digest.update(data: Data((name + "\0").utf8))
                let stream = try FileHandle(forReadingFrom: file)
                defer { try? stream.close() }
                while let data = try stream.read(upToCount: 1024 * 1024), !data.isEmpty {
                    digest.update(data: data)
                }
            }
            let environment = ProcessInfo.processInfo.environment.filter { key, _ in
                ["QLIP_SPEC_", "QLIP_DSPARK_", "QLIP_COMPACT_", "QLIP_FUSED_"].contains {
                    key.hasPrefix($0)
                }
            }
            let encoded = try JSONSerialization.data(withJSONObject: environment,
                options: [.sortedKeys])
            return ["engine_path": root.path,
                    "installed_artifacts_sha256": digest.finalize().map { String(format: "%02x", $0) }.joined(),
                    "identity_scope": "installed regular files, excluding qlip_key.bin and hidden files",
                    "installed_artifact_count": String(files.count),
                    "runtime_load_environment": String(decoding: encoded, as: UTF8.self),
                    "request_legacy_environment": "disabled",
                    "cpu_predraft": "disabled",
                    "compute_device_hint": "npu"]
        }.value
    }
    static func algorithm(_ root: URL) -> String? {
        for directory in [root, root.appendingPathComponent("llm")] {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("model_spec.json")),
                  let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arch = value["arch"] as? [String: Any],
                  let decoder = arch["decoder"] as? [String: Any],
                  let spec = decoder["speculative"] as? [String: Any],
                  let algorithm = spec["algorithm"] as? String else { continue }
            return algorithm
        }
        return nil
    }

    static func usesSmokeTokenizer(_ root: URL?) -> Bool {
        guard let root, let data = try? Data(contentsOf: root.appendingPathComponent("tokenizer/tokenizer.json")) else { return false }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return digest == "df1d8d5ec5d091b460562ffd545e4a5e91d17d4a0db7ebe733be34ed374377bd"
    }
    static func supports(_ root: URL?) -> Bool {
        guard let root else { return false }
        return [root, root.appendingPathComponent("llm")].contains { directory in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("model_spec.json")),
                let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let arch = value["arch"] as? [String: Any],
                let decoder = arch["decoder"] as? [String: Any]
            else { return false }
            if let fused = decoder["fused_speculative"] as? [String: Any], !fused.isEmpty { return true }
            let spec = decoder["speculative"] as? [String: Any]
            return (spec?["num_draft_tokens"] as? Int ?? 0) > 0
        }
    }
}

@MainActor
final class BenchActivity: ObservableObject {
    static let shared = BenchActivity()
    @Published var busy = false
    func begin() -> Bool {
        guard !busy else { return false }
        busy = true
        UIApplication.shared.isIdleTimerDisabled = true
        return true
    }
    func end() {
        busy = false
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

struct SmokePrompt: Decodable, Sendable {
    let id: String
    let domain: String
    let prompt: String
    let input_ids: [Int]
    static let datasets = ["prompt_tokens_k1256", "prompt_tokens_ext_20260901", "prompt_tokens_agentic_20260901"]
    static let titles = ["Canon · 100 prompts", "Extended · 320 prompts", "Agentic / BFCL · 96 prompts"]
    static func load(dataset: String) throws -> [SmokePrompt] {
        struct Row: Decodable {
            let id: String
            let source: String
            let prompt_tokens: Int
            let input_ids: [Int]
        }
        struct Pack: Decodable { let rows: [Row] }
        guard datasets.contains(dataset), let root = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
        let url = root.appendingPathComponent("BenchmarkData/scion/\(dataset).json")
        let pack = try JSONDecoder().decode(Pack.self, from: Data(contentsOf: url))
        guard !pack.rows.isEmpty, Set(pack.rows.map(\.id)).count == pack.rows.count,
            pack.rows.allSatisfy({ !$0.input_ids.isEmpty && $0.input_ids.count == $0.prompt_tokens })
        else { throw CocoaError(.fileReadCorruptFile) }
        return pack.rows.map { Self(id: $0.id, domain: $0.source, prompt: "", input_ids: $0.input_ids) }
    }
}

struct SmokeMeasurement: Codable, Sendable {
    let id: String
    let domain: String
    let round: Int
    let speculative: Bool
    let promptTokens: Int
    let promptEncoding: String
    let decodeTokens: Int
    let cycles: Int
    let steps: Int
    let forwardSeconds: Double
    let decodeSeconds: Double
    let prefillSeconds: Double
    let requestSeconds: Double
    let stopReason: String
    let text: String
    var tokS: Double { decodeSeconds > 0 ? Double(decodeTokens) / decodeSeconds : 0 }
    var tau: Double? { cycles > 0 ? Double(decodeTokens) / Double(cycles) : nil }

    static func run(_ llm: TheStageLLM, prompt: SmokePrompt, config: LLMGenerationConfig,
                    round: Int, speculative: Bool, useStoredTokens: Bool) async throws -> Self {
        try await Task.detached(priority: .userInitiated) {
            let start = ProcessInfo.processInfo.systemUptime
            let result = useStoredTokens
                ? try llm.infer(prompt_token_ids: prompt.input_ids, config: config)
                : try llm.infer(prompt: prompt.prompt, config: config)
            let wall = ProcessInfo.processInfo.systemUptime - start
            guard let data = try llm.generation_trace_json(),
                let trace = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let summary = trace["summary"] as? [String: Any],
                let tokens = summary["decode_tokens"] as? Int,
                let cycles = summary["cycles"] as? Int else { throw CocoaError(.coderReadCorrupt) }
            if (!speculative && cycles != 0) || (speculative && tokens > 0 && cycles == 0) {
                throw NSError(domain: "EngineBench", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Requested decoding mode was not executed"])
            }
            return Self(id: prompt.id, domain: prompt.domain, round: round,
                        speculative: speculative, promptTokens: result.prompt_tokens,
                        promptEncoding: useStoredTokens ? "stored-lfm-token-ids" : "model-chat-template",
                        decodeTokens: tokens, cycles: cycles, steps: result.decode_step_count,
                        forwardSeconds: result.decode_forward_seconds, decodeSeconds: result.decode_seconds,
                        prefillSeconds: result.prefill_seconds, requestSeconds: wall,
                        stopReason: trace["termination"] as? String ?? result.stop_reason,
                        text: result.text)
        }.value
    }
}

struct ASRMeasurement: Codable {
    var preprocessSeconds: Double? = nil
    var residualSeconds: Double? = nil
    var chunkCount: Int? = nil
    var acceptedDrafts: Int? = nil
    var startedAt: Date? = nil
    var thermalBefore: Int? = nil
    var thermalAfter: Int? = nil
    var lowPowerMode: Bool? = nil
    var diagnostic: ASRDiagnostic? = nil
    var clip: String? = nil
    var language: String? = nil
    var prefillSeconds: Double? = nil
    var encodeSeconds: Double? = nil
    var matchesWarmup: Bool? = nil
    let round: Int
    let speculative: Bool
    let audioSeconds: Double
    let requestSeconds: Double
    let decodeSeconds: Double
    let decodeTokens: Int
    let cycles: Int
    let tokens: [Int]?
    let text: String
}

// Preserve the complete SDK trace schema, including future diagnostic fields.
indirect enum BenchJSON: Codable, Sendable {
    case object([String: BenchJSON]), array([BenchJSON]), string(String)
    case number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([BenchJSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: BenchJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}
struct ASRDiagnostic: Codable, Sendable {
    let role: String
    // convertFromSnakeCase maps request_id to requestId (not requestID).
    let requestId: String
    let requestSeconds: Double
    let thermalBefore: Int
    let thermalAfter: Int
    let chunks: [BenchJSON]
    let expectedChunks: Int
    let complete: Bool
    let error: String?
}
