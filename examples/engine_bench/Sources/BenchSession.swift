// Session-wide benchmark log + JSON share support.
//
// Every completed Benchmark run (LLM / TTS / ASR tab) appends a structured
// BenchRecord here. The share button exports the whole session as a .json
// FILE (never plain text) through the standard system share sheet, with
// device identity in the envelope so results from different phones stay
// attributable.
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// --------------------------------------------------------------------------------------
// BenchRecord
// --------------------------------------------------------------------------------------
// One benchmark summary. Optional fields are per-kind (llm / tts / asr);
// synthesized Codable uses encodeIfPresent, so nils vanish from the JSON.
struct BenchRecord: Codable {
    let kind: String
    let model: String
    let voice: String?
    let timestamp: Date
    let prompt: String?
    let runs: Int
    let maxNewTokens: Int?

    // Decode throughput (LLM/TTS: generated tok/s; ASR: decode tok/s).
    let bestTokS: Double?
    let medianTokS: Double?
    let meanTokS: Double?

    // LLM-only step split + latency.
    let predictMsStep: Double?
    let hostMsStep: Double?
    let ttftMs: Double?
    let tokens: Int?

    // TTS realtime factor (audio seconds per synthesis second).
    let bestRtf: Double?
    let medianRtf: Double?

    // ASR realtime factor + encoder latency.
    let bestRtfx: Double?
    let medianRtfx: Double?
    let medianEncodeMs: Double?

    // Raw per-run values so exported sessions stay analyzable.
    let perRunTokS: [Double]?
    let perRunRtf: [Double]?
    let perRunRtfx: [Double]?
    let perRunEncodeMs: [Double]?

    // ----------------------------------------------------------------------------------
    // Factories
    // ----------------------------------------------------------------------------------
    static func llm(
        model: String,
        prompt: String,
        runs: Int,
        maxNewTokens: Int,
        row: BenchRow,
        perRunTokS: [Double]
    ) -> BenchRecord {
        BenchRecord(
            kind: "llm", model: model, voice: nil, timestamp: Date(),
            prompt: prompt, runs: runs, maxNewTokens: maxNewTokens,
            bestTokS: row.bestTokS, medianTokS: row.medianTokS,
            meanTokS: row.meanTokS, predictMsStep: row.predictMsStep,
            hostMsStep: row.hostMsStep, ttftMs: row.ttftMs,
            tokens: row.tokens,
            bestRtf: nil, medianRtf: nil,
            bestRtfx: nil, medianRtfx: nil, medianEncodeMs: nil,
            perRunTokS: perRunTokS, perRunRtf: nil, perRunRtfx: nil,
            perRunEncodeMs: nil
        )
    }

    static func tts(
        model: String,
        voice: String,
        text: String,
        runs: Int,
        perRunTokS: [Double],
        perRunRtf: [Double]
    ) -> BenchRecord {
        BenchRecord(
            kind: "tts", model: model, voice: voice, timestamp: Date(),
            prompt: text, runs: runs, maxNewTokens: nil,
            bestTokS: perRunTokS.max(), medianTokS: median(perRunTokS),
            meanTokS: nil, predictMsStep: nil, hostMsStep: nil,
            ttftMs: nil, tokens: nil,
            bestRtf: perRunRtf.max(), medianRtf: median(perRunRtf),
            bestRtfx: nil, medianRtfx: nil, medianEncodeMs: nil,
            perRunTokS: perRunTokS, perRunRtf: perRunRtf, perRunRtfx: nil,
            perRunEncodeMs: nil
        )
    }

    static func asr(
        model: String,
        runs: Int,
        perRunRtfx: [Double],
        perRunTokS: [Double],
        perRunEncodeS: [Double]
    ) -> BenchRecord {
        BenchRecord(
            kind: "asr", model: model, voice: nil, timestamp: Date(),
            prompt: nil, runs: runs, maxNewTokens: nil,
            bestTokS: perRunTokS.max(), medianTokS: median(perRunTokS),
            meanTokS: nil, predictMsStep: nil, hostMsStep: nil,
            ttftMs: nil, tokens: nil,
            bestRtf: nil, medianRtf: nil,
            bestRtfx: perRunRtfx.max(), medianRtfx: median(perRunRtfx),
            medianEncodeMs: median(perRunEncodeS.map { $0 * 1000 }),
            perRunTokS: perRunTokS, perRunRtf: nil, perRunRtfx: perRunRtfx,
            perRunEncodeMs: perRunEncodeS.map { $0 * 1000 }
        )
    }

    private static func median(_ xs: [Double]) -> Double? {
        let s = xs.sorted()
        guard !s.isEmpty else { return nil }
        let m = s.count / 2
        return s.count % 2 == 0 ? (s[m - 1] + s[m]) / 2 : s[m]
    }
}

// --------------------------------------------------------------------------------------
// BenchSession
// --------------------------------------------------------------------------------------
@MainActor
final class BenchSession: ObservableObject {
    static let shared = BenchSession()
    private init() {}

    @Published private(set) var records: [BenchRecord] = []

    func add(_ record: BenchRecord) {
        records.append(record)
    }
}

// --------------------------------------------------------------------------------------
// BenchDeviceInfo / BenchReport
// --------------------------------------------------------------------------------------
struct BenchDeviceInfo: Codable {
    let name: String
    // Hardware identifier (e.g. "iPhone17,2") — the value that actually
    // matters for benchmarks; UIDevice.name is privacy-genericized on
    // iOS 16+ without the user-assigned-device-name entitlement.
    let modelIdentifier: String
    let system: String
    let osVersion: String

    static func current() -> BenchDeviceInfo {
        var sys = utsname()
        uname(&sys)
        let machine = withUnsafeBytes(of: &sys.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let device = UIDevice.current
        return BenchDeviceInfo(
            name: device.name,
            modelIdentifier: machine,
            system: device.systemName,
            osVersion: device.systemVersion
        )
    }
}

struct BenchReport: Codable {
    let device: BenchDeviceInfo
    let createdAt: Date
    let results: [BenchRecord]

    func jsonData() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        enc.keyEncodingStrategy = .convertToSnakeCase
        return try enc.encode(self)
    }

    func suggestedFileName() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = fmt.string(from: createdAt)
        return "enginebench-\(device.modelIdentifier)-\(stamp).json"
    }
}

// --------------------------------------------------------------------------------------
// BenchReportFile — Transferable so ShareLink hands receivers a real .json file
// --------------------------------------------------------------------------------------
struct BenchReportFile: Transferable {
    let report: BenchReport

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { file in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(file.report.suggestedFileName())
            try file.report.jsonData().write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

// --------------------------------------------------------------------------------------
// SessionShareButton — standard share icon, disabled until something was measured
// --------------------------------------------------------------------------------------
struct SessionShareButton: View {
    @ObservedObject private var session = BenchSession.shared

    var body: some View {
        ShareLink(
            item: BenchReportFile(report: BenchReport(
                device: .current(),
                createdAt: Date(),
                results: session.records
            )),
            preview: SharePreview("EngineBench results")
        ) {
            Image(systemName: "square.and.arrow.up")
        }
        .disabled(session.records.isEmpty)
    }
}
