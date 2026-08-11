import AVFoundation
import SwiftUI
import TheStageSDK

// --------------------------------------------------------------------------------------
// TTS catalog
// --------------------------------------------------------------------------------------
// One entry per TTS bundle under `BundledModels/<name>/`. `family` picks the
// SDK pipeline class (NeuTTS multilingual vs Qwen3-TTS dual-LM); `hfRepo` is
// the fallback when the bundle isn't baked into the app (same bundled-first
// rule as the LLM catalog).
enum TTSFamily: Hashable {
    case neutts
    case qwen3Tts
}

struct BundledTTSModel: Identifiable, Hashable {
    let name: String
    let displayName: String
    let voices: [String]
    let hfRepo: String
    /// Optional HF revision override. `nil` → ``ModelRevisionMap``.
    let revision: String?
    let family: TTSFamily

    var id: String { name }

    func enginesPath() -> String {
        // Path-based only — Bundle.url(forResource:) splits on `.`
        // (lfm2.5 / qwen3-0.6b / qwen3-tts-12hz-0.6b-base).
        let dir = Bundle.main.resourceURL?
            .appendingPathComponent("BundledModels", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        if let dir, FileManager.default.fileExists(atPath: dir.path) {
            return dir.path
        }
        return hfRepo
    }
}

enum TTSCatalog {
    static let all: [BundledTTSModel] = [
        BundledTTSModel(
            name: "neutts-nano-multilingual",
            displayName: "NeuTTS nano multilingual",
            voices: ["dave", "bril", "jo", "paul"],
            hfRepo: "TheStageAI/neutts-nano-multilingual",
            revision: nil,
            family: .neutts
        ),
        BundledTTSModel(
            name: "qwen3-tts-12hz-0.6b-base",
            displayName: "Qwen3-TTS 0.6b",
            voices: ["b_ref", "donald_trump", "elon_musk",
                     "jensen_huang", "joe_biden"],
            hfRepo: "TheStageAI/Qwen3-TTS-12Hz-0.6B-Base",
            revision: nil,
            family: .qwen3Tts
        ),
    ]
    static var first: BundledTTSModel { all[0] }
}

// --------------------------------------------------------------------------------------
// BenchTTS — family-agnostic handle over the two SDK pipeline classes
// --------------------------------------------------------------------------------------
// Both pipelines subclass TheStageTTSPipeline; this adds the batch infer +
// convenience stream entry points the bench needs under one type.
protocol BenchTTS: AnyObject {
    func bench_infer(text: String) -> TTSResult
    func bench_stream(text: String) -> AsyncStream<InferenceStreamChunk>
}

extension NeuTTSMultilingualPipeline: BenchTTS {
    func bench_infer(text: String) -> TTSResult { infer(text: text) }
    func bench_stream(text: String) -> AsyncStream<InferenceStreamChunk> {
        infer_stream(text: text)
    }
}

extension Qwen3TTSPipeline: BenchTTS {
    func bench_infer(text: String) -> TTSResult { infer(text: text) }
    func bench_stream(text: String) -> AsyncStream<InferenceStreamChunk> {
        infer_stream(text: text)
    }
}

// --------------------------------------------------------------------------------------
// TTSHost — one-slot pipeline cache (keyed by model + voice)
// --------------------------------------------------------------------------------------
@MainActor
final class TTSHost {
    static let shared = TTSHost()
    private init() {}

    private var current: (key: String, tts: any BenchTTS)?

    func pipeline(
        for model: BundledTTSModel,
        voice: String,
        onProgress: LoadProgressHandler? = nil
    ) async throws -> any BenchTTS {
        try await LLMHost.shared.ensureInitialized()
        let key = "\(model.name)/\(voice)"
        if let current, current.key == key {
            return current.tts
        }
        current = nil
        let tts: any BenchTTS
        switch model.family {
        case .neutts:
            tts = try await NeuTTSMultilingualPipeline(
                engines_path: model.enginesPath(),
                voice_id: voice,
                device: "npu",
                revision: model.revision,
                on_load_progress: onProgress
            )
        case .qwen3Tts:
            tts = try await Qwen3TTSPipeline(
                engines_path: model.enginesPath(),
                voice_id: voice,
                device: "npu",
                revision: model.revision,
                on_load_progress: onProgress
            )
        }
        current = (key, tts)
        return tts
    }
}

// --------------------------------------------------------------------------------------
// TTSBenchModel
// --------------------------------------------------------------------------------------
@MainActor
final class TTSBenchModel: ObservableObject {
    @Published var selected: BundledTTSModel = TTSCatalog.first
    @Published var voice: String = TTSCatalog.first.voices[0]
    @Published var text = "Hello! This is a test of the new text to speech model."
    @Published var statsLine = ""
    @Published var status = "tap Synthesize"
    @Published var rows: [String] = []
    @Published var running = false
    @Published var runs = 3
    @Published var loadPhase: String?
    @Published var loadFraction = 0.0

    private var player: StreamPlayer?

    private func progressHandler() -> LoadProgressHandler {
        { [weak self] p in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.loadFraction = p.fraction
                self.loadPhase = p.phase == .ready ? nil : "\(p.phase)"
            }
        }
    }

    func synthesize() {
        guard !running else { return }
        running = true
        statsLine = ""
        status = "loading \(selected.displayName) (\(voice))…"
        let model = selected
        let v = voice
        let t = text

        Task {
            do {
                let tts = try await TTSHost.shared.pipeline(
                    for: model, voice: v, onProgress: progressHandler()
                )
                self.loadPhase = nil
                self.status = "synthesizing…"
                // Streaming: playback starts the moment the first sentence's
                // audio lands; later chunks are scheduled behind it gaplessly.
                self.player?.stop()
                self.player = StreamPlayer(rate: 24000)
                let t0 = CFAbsoluteTimeGetCurrent()
                var ttfa: Double? = nil
                var samples = 0
                for await chunk in tts.bench_stream(text: t) {
                    if let pcm = chunk.audio, !pcm.isEmpty {
                        if ttfa == nil {
                            ttfa = CFAbsoluteTimeGetCurrent() - t0
                            self.status = String(
                                format: "playing… (first audio in %.2fs)", ttfa!
                            )
                        }
                        samples += pcm.count
                        self.player?.enqueue(pcm)
                    }
                    if chunk.is_final {
                        let dur = Double(samples) / 24000
                        let total = chunk.total_seconds
                            ?? (CFAbsoluteTimeGetCurrent() - t0)
                        // Same convention as batch TTSResult.rtf: audio
                        // seconds per synthesis second (higher = faster
                        // than realtime).
                        let rtf = total > 0 ? dur / total : 0
                        self.statsLine = String(
                            format: "%.2fs audio · TTFA %.2fs · rtf %.2f · %.1f tok/s",
                            dur, ttfa ?? 0, rtf, chunk.tokens_per_second ?? 0
                        )
                    }
                }
                self.status = "done"
                self.running = false
            } catch {
                self.loadPhase = nil
                self.status = "error: \(error.localizedDescription)"
                self.running = false
            }
        }
    }

    func benchmark() {
        guard !running else { return }
        running = true
        statsLine = ""
        status = "preparing…"
        let model = selected
        let v = voice
        let t = text
        let n = max(1, runs)

        Task {
            do {
                let tts = try await TTSHost.shared.pipeline(
                    for: model, voice: v, onProgress: progressHandler()
                )
                self.loadPhase = nil
                _ = await Self.runInfer(tts, t)   // warmup
                var tps: [Double] = []
                var rtf: [Double] = []
                for k in 0 ..< n {
                    self.status = "run \(k + 1)/\(n)…"
                    let r = await Self.runInfer(tts, t)
                    tps.append(r.tokens_per_second)
                    rtf.append(r.rtf)
                }
                let line = String(
                    format: "%@/%@  tok/s best %.1f median %.1f · rtf median %.2f",
                    model.displayName, v,
                    tps.max() ?? 0, Self.median(tps), Self.median(rtf)
                )
                BenchSession.shared.add(.tts(
                    model: model.displayName,
                    voice: v,
                    text: t,
                    runs: n,
                    perRunTokS: tps,
                    perRunRtf: rtf
                ))
                self.rows.removeAll { $0.hasPrefix("\(model.displayName)/\(v)") }
                self.rows.append(line)
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
        _ tts: any BenchTTS, _ text: String
    ) async -> TTSResult {
        await Task.detached(priority: .userInitiated) {
            tts.bench_infer(text: text)
        }.value
    }

    private static func median(_ xs: [Double]) -> Double {
        let s = xs.sorted()
        guard !s.isEmpty else { return 0 }
        let m = s.count / 2
        return s.count % 2 == 0 ? (s[m - 1] + s[m]) / 2 : s[m]
    }

    // (batch playback replaced by StreamPlayer)
}

// --------------------------------------------------------------------------------------
// StreamPlayer — gapless streaming PCM playback (AVAudioEngine + player node)
// --------------------------------------------------------------------------------------
final class StreamPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format: AVAudioFormat

    init(rate: Double) {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: rate,
            channels: 1, interleaved: false
        )!
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try? engine.start()
        node.play()
    }

    func enqueue(_ pcm: [Float]) {
        guard let buf = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.count)
        ) else { return }
        buf.frameLength = AVAudioFrameCount(pcm.count)
        pcm.withUnsafeBufferPointer { src in
            buf.floatChannelData![0].update(
                from: src.baseAddress!, count: pcm.count
            )
        }
        node.scheduleBuffer(buf)
    }

    func stop() {
        node.stop()
        engine.stop()
    }
}

// --------------------------------------------------------------------------------------
// TTSBenchView
// --------------------------------------------------------------------------------------
struct TTSBenchView: View {
    @StateObject var model = TTSBenchModel()
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("TheStage SDK · TTS bench")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                SessionShareButton()
            }
            .padding(.horizontal)

            Picker("Model", selection: $model.selected) {
                ForEach(TTSCatalog.all) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.running)
            .padding(.horizontal)
            .onChange(of: model.selected) { _, m in
                model.voice = m.voices[0]
            }

            Picker("Voice", selection: $model.voice) {
                ForEach(model.selected.voices, id: \.self) { v in
                    Text(v).tag(v)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.running)
            .padding(.horizontal)

            TextField("Text", text: $model.text, axis: .vertical)
                .lineLimit(1 ... 4)
                .textFieldStyle(.roundedBorder)
                .focused($textFocused)
                .disabled(model.running)
                .padding(.horizontal)

            Stepper("runs \(model.runs)", value: $model.runs, in: 1 ... 10)
                .font(.system(.caption, design: .monospaced))
                .disabled(model.running)
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
                        Text(String(format: "%@ %.0f%%", phase, model.loadFraction * 100))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
            }

            HStack(spacing: 10) {
                Button {
                    textFocused = false
                    model.synthesize()
                } label: {
                    buttonLabel("Synthesize", color: .blue)
                }
                .disabled(model.running)

                Button {
                    textFocused = false
                    model.benchmark()
                } label: {
                    buttonLabel("Benchmark", color: .purple)
                }
                .disabled(model.running)
            }
            .padding(.horizontal)

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

    private func buttonLabel(_ title: String, color: Color) -> some View {
        Text(model.running ? "…" : title)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(model.running ? Color.gray : color)
            .foregroundColor(.white)
            .cornerRadius(10)
    }
}
