import AVFoundation
import SwiftUI
import TheStageSDK

// --------------------------------------------------------------------------------------
// ASR catalog
// --------------------------------------------------------------------------------------
// One entry per ASR bundle under `BundledModels/<name>/`. Same bundled-first /
// HF-fallback rule as the LLM/TTS catalogs. An empty `hfRepo` means the model
// is dev-bundle only (no published engines yet).
enum ASRFamily: Hashable {
    case qwen3
    case whisper
}

struct BundledASRModel: Identifiable, Hashable {
    let name: String
    let displayName: String
    let hfRepo: String
    /// Optional HF revision override. `nil` → ``ModelRevisionMap``.
    let revision: String?
    let family: ASRFamily

    var id: String { name }

    func enginesPath() -> String? {
        // Path-based only — Bundle.url(forResource:) splits on `.`.
        if let dir = bundledDir() { return dir.path }
        return hfRepo.isEmpty ? nil : hfRepo
    }

    /// True when the engines dir is shipped inside the app (not HF-only).
    var isBundled: Bool { bundledDir() != nil }

    private func bundledDir() -> URL? {
        let dir = Bundle.main.resourceURL?
            .appendingPathComponent("BundledModels", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        if let dir, FileManager.default.fileExists(atPath: dir.path) {
            return dir
        }
        return nil
    }
}

enum ASRCatalog {
    static let all: [BundledASRModel] = [
        BundledASRModel(
            name: "thewhisper-large-v3-turbo",
            displayName: "Whisper turbo",
            hfRepo: "TheStageAI/thewhisper-large-v3-turbo",
            revision: nil,
            family: .whisper
        ),
        BundledASRModel(
            name: "qwen3-asr-0.6b",
            displayName: "Qwen3-ASR 0.6b",
            hfRepo: "TheStageAI/Qwen3-ASR-0.6B",
            revision: nil,
            family: .qwen3
        ),
    ]
    static var first: BundledASRModel { all[0] }
}

// --------------------------------------------------------------------------------------
// BenchASR — family-agnostic handle (Whisper + Qwen3)
// --------------------------------------------------------------------------------------
protocol BenchASR: AnyObject {
    func bench_infer(audio: [Float]) -> ASRResult
    func release()
}

extension WhisperPipeline: BenchASR {
    func bench_infer(audio: [Float]) -> ASRResult {
        infer(audio: audio, language: "en")
    }
}

extension Qwen3ASRPipeline: BenchASR {
    func bench_infer(audio: [Float]) -> ASRResult {
        infer(audio: audio, language: "en")
    }
}

// --------------------------------------------------------------------------------------
// ASRHost — one-slot pipeline cache
// --------------------------------------------------------------------------------------
@MainActor
final class ASRHost {
    static let shared = ASRHost()
    private init() {}

    private var current: (key: String, asr: any BenchASR)?

    func pipeline(
        for model: BundledASRModel,
        onProgress: LoadProgressHandler? = nil
    ) async throws -> any BenchASR {
        try await LLMHost.shared.ensureInitialized()
        if let current, current.key == model.name {
            return current.asr
        }
        // Release the previous decoder before loading the next (ANE memory).
        current?.asr.release()
        current = nil
        guard let path = model.enginesPath() else {
            throw NSError(domain: "ASRBench", code: 1, userInfo: [
                NSLocalizedDescriptionKey:
                    "\(model.displayName): no bundled engines and no HF repo. "
                    + "Set hfRepo on the catalog entry.",
            ])
        }
        if model.isBundled {
            print("[ASRBench] loading bundled \(model.name) from \(path)")
        } else {
            print(
                "[ASRBench] loading \(model.name) from HF "
                    + "(revision via ModelRevisionMap)"
            )
        }
        let asr: any BenchASR
        switch model.family {
        case .whisper:
            asr = try await WhisperPipeline(
                engines_path: path,
                device: "npu",
                revision: model.revision,
                on_load_progress: onProgress
            )
        case .qwen3:
            asr = try await Qwen3ASRPipeline(
                engines_path: path,
                device: "npu",
                revision: model.revision,
                on_load_progress: onProgress
            )
        }
        current = (model.name, asr)
        return asr
    }
}

// --------------------------------------------------------------------------------------
// ASRBenchModel
// --------------------------------------------------------------------------------------
@MainActor
final class ASRBenchModel: ObservableObject {
    @Published var selected: BundledASRModel = ASRCatalog.first
    @Published var statsLine = ""
    @Published var status = "tap Record or Benchmark"
    @Published var transcript = ""
    @Published var rows: [String] = []
    @Published var running = false
    @Published var recording = false
    @Published var runs = 3
    @Published var loadPhase: String?
    @Published var loadFraction = 0.0

    private var inputEngine: AudioInputEngine?
    private var captureTask: Task<Void, Never>?
    private var captured: [Float] = []
    private static let maxRecordSeconds = 60

    private func progressHandler() -> LoadProgressHandler {
        { [weak self] p in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.loadFraction = p.fraction
                self.loadPhase = p.phase == .ready ? nil : "\(p.phase)"
            }
        }
    }

    // -- record & transcribe ------------------------------------------------
    func toggleRecord() {
        if recording {
            stopAndTranscribe()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard !running else { return }
        transcript = ""
        statsLine = ""
        captured = []
        do {
            var cfg = AudioInputConfig()
            cfg.sample_rate = 16000
            cfg.channels = 1
            let engine = AudioInputEngine(config: cfg)
            try engine.start()
            inputEngine = engine
            recording = true
            status = "recording… tap Stop when done"
            captureTask = Task { [weak self] in
                for await chunk in engine.stream {
                    guard let self else { return }
                    await MainActor.run {
                        self.captured.append(contentsOf: chunk)
                        let secs = Double(self.captured.count) / 16000.0
                        self.status = String(
                            format: "recording… %.1fs (tap Stop)", secs
                        )
                        if self.captured.count
                            > Self.maxRecordSeconds * 16000 {
                            self.stopAndTranscribe()
                        }
                    }
                }
            }
        } catch {
            status = "mic error: \(error.localizedDescription)"
        }
    }

    private func stopAndTranscribe() {
        guard recording else { return }
        recording = false
        captureTask?.cancel()
        captureTask = nil
        inputEngine?.stop()
        inputEngine = nil

        let audio = captured
        captured = []
        guard audio.count > 1600 else {
            status = "recording too short"
            return
        }
        running = true
        status = "loading \(selected.displayName)…"
        let model = selected

        Task {
            do {
                let asr = try await ASRHost.shared.pipeline(
                    for: model, onProgress: progressHandler()
                )
                self.loadPhase = nil
                self.status = "transcribing…"
                let r = await Self.runInfer(asr, audio)
                let m = r.metrics
                self.transcript = r.text.isEmpty ? "(no speech)" : r.text
                self.statsLine = String(
                    format: "%.1fs audio · dec %.2fs · rtfx %.2f · %.1f tok/s",
                    m.audio_seconds, m.decode_seconds, m.rtfx,
                    m.tokens_per_second
                )
                self.status = "done"
                self.running = false
            } catch {
                self.loadPhase = nil
                self.status = "error: \(error.localizedDescription)"
                self.running = false
            }
        }
    }

    // -- benchmark ------------------------------------------------------------
    func benchmark() {
        guard !running, !recording else { return }
        guard let audio = Self.loadBenchAudio() else {
            status = "bench audio missing (BundledModels/asr_fixtures)"
            return
        }
        running = true
        statsLine = ""
        status = "preparing…"
        let model = selected
        let n = max(1, runs)

        Task {
            do {
                let asr = try await ASRHost.shared.pipeline(
                    for: model, onProgress: progressHandler()
                )
                self.loadPhase = nil
                self.status = "warmup…"
                _ = await Self.runInfer(asr, Array(audio.prefix(16000)))
                var rtfx: [Double] = []
                var tps: [Double] = []
                var enc: [Double] = []
                for k in 0 ..< n {
                    self.status = "run \(k + 1)/\(n)…"
                    let r = await Self.runInfer(asr, audio)
                    rtfx.append(r.metrics.rtfx)
                    tps.append(r.metrics.tokens_per_second)
                    enc.append(r.metrics.encode_seconds)
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
                let line = String(
                    format: "%@  rtfx best %.2f med %.2f · dec med %.1f tok/s"
                        + " · enc med %.0f ms",
                    model.displayName,
                    rtfx.max() ?? 0, Self.median(rtfx), Self.median(tps),
                    Self.median(enc) * 1000
                )
                self.rows.removeAll { $0.hasPrefix(model.displayName) }
                self.rows.append(line)
                BenchSession.shared.add(.asr(
                    model: model.displayName,
                    runs: n,
                    perRunRtfx: rtfx,
                    perRunTokS: tps,
                    perRunEncodeS: enc
                ))
                self.statsLine = line
                self.status = "done"
                self.running = false
            } catch {
                self.loadPhase = nil
                self.status = "error: \(error.localizedDescription)"
                self.running = false
            }
        }
    }

    // Synchronous SDK infer off the main actor (no UI writes mid-measure).
    private nonisolated static func runInfer(
        _ asr: any BenchASR, _ audio: [Float]
    ) async -> ASRResult {
        await Task.detached(priority: .userInitiated) {
            asr.bench_infer(audio: audio)
        }.value
    }

    private static func loadBenchAudio() -> [Float]? {
        // Path-based only — Bundle.url(forResource:) is unreliable with
        // nested folder references (same issue as dotted model names).
        let url = Bundle.main.resourceURL?
            .appendingPathComponent(
                "BundledModels/asr_fixtures/bench_asr.wav"
            )
        guard let url, FileManager.default.fileExists(atPath: url.path),
              let file = try? AVAudioFile(forReading: url)
        else { return nil }
        guard let buf = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ), (try? file.read(into: buf)) != nil,
            let data = buf.floatChannelData
        else { return nil }
        return Array(UnsafeBufferPointer(
            start: data[0], count: Int(buf.frameLength)
        ))
    }

    private static func median(_ xs: [Double]) -> Double {
        let s = xs.sorted()
        guard !s.isEmpty else { return 0 }
        let m = s.count / 2
        return s.count % 2 == 0 ? (s[m - 1] + s[m]) / 2 : s[m]
    }
}

// --------------------------------------------------------------------------------------
// ASRBenchView
// --------------------------------------------------------------------------------------
struct ASRBenchView: View {
    @StateObject var model = ASRBenchModel()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("TheStage SDK · ASR bench")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                SessionShareButton()
            }
            .padding(.horizontal)

            Picker("Model", selection: $model.selected) {
                ForEach(ASRCatalog.all) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.running || model.recording)
            .padding(.horizontal)

            Stepper("runs \(model.runs)", value: $model.runs, in: 1 ... 10)
                .font(.system(.caption, design: .monospaced))
                .disabled(model.running || model.recording)
                .padding(.horizontal)

            if let phase = model.loadPhase {
                VStack(alignment: .leading, spacing: 2) {
                    if phase == "loading" {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("loading (first run compiles the model)…")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ProgressView(value: model.loadFraction)
                        Text(String(
                            format: "%@ %.0f%%", phase,
                            model.loadFraction * 100
                        ))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
            }

            HStack(spacing: 10) {
                Button {
                    model.toggleRecord()
                } label: {
                    Text(model.recording ? "Stop" : "Record")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(model.recording ? Color.red
                            : (model.running ? Color.gray : Color.blue))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(model.running)

                Button {
                    model.benchmark()
                } label: {
                    Text(model.running ? "…" : "Benchmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            model.running || model.recording
                                ? Color.gray : Color.purple
                        )
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(model.running || model.recording)
            }
            .padding(.horizontal)

            if !model.transcript.isEmpty {
                ScrollView {
                    Text(model.transcript)
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal)
            }

            if !model.rows.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.rows, id: \.self) { r in
                        Text(r)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal)
            }

            Spacer()

            Text(model.statsLine.isEmpty ? model.status : model.statsLine)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }
}
