// EngineBench — iPhone benchmark app driving the public SDK (TheStageLLM).
//
// Two clearly separated modes so numbers aren't tainted by text rendering:
//   • Generate  — llm.infer_stream, per-token UI updates (feel + honest TTFT).
//   • Benchmark — llm.infer (non-streaming): warmup + N runs with ZERO UI
//                 writes during decode, so SwiftUI never re-renders mid-measure.
//                 Reported metrics come from LLMResult (SDK-timed decode loop).
import SwiftUI
import TheStageSDK

// --------------------------------------------------------------------------------------
// BenchRow
// --------------------------------------------------------------------------------------
struct BenchRow: Identifiable {
    let id = UUID()
    let model: String
    let bestTokS: Double
    let medianTokS: Double
    let meanTokS: Double
    let predictMsStep: Double
    let hostMsStep: Double
    let ttftMs: Double
    let tokens: Int
}

// --------------------------------------------------------------------------------------
// BenchModel
// --------------------------------------------------------------------------------------
@MainActor
final class BenchModel: ObservableObject {
    @Published var selected: BundledModel = ModelCatalog.first
    @Published var prompt = "List 25 facts about London."
    @Published var output = ""
    @Published var statsLine = ""
    @Published var status = "tap Generate"
    @Published var rows: [BenchRow] = []
    @Published var running = false

    @Published var maxNew = 128
    @Published var runs = 5

    /// Model-load progress (HF download / extract / decrypt+compile). `nil`
    /// when no load is in flight; fraction is monotonic 0...1 across phases.
    @Published var loadPhase: String?
    @Published var loadFraction = 0.0

    private static let warmupRuns = 2
    private static let runCooldownNs: UInt64 = 2_000_000_000

    /// SDK `LoadProgress` -> published UI state (hop back to the main actor).
    private func progressHandler() -> LoadProgressHandler {
        { [weak self] p in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.loadFraction = p.fraction
                self.loadPhase = p.phase == .ready ? nil : "\(p.phase)"
            }
        }
    }

    // ----------------------------------------------------------------------------------
    // Generate (streaming)
    // ----------------------------------------------------------------------------------
    func generate() {
        guard !running else { return }
        running = true
        output = ""
        statsLine = ""
        status = "loading \(selected.displayName)…"
        let model = selected
        let promptText = prompt
        let cap = maxNew

        Task {
            do {
                let llm = try await LLMHost.shared.llm(
                    for: model, onProgress: progressHandler()
                )
                self.loadPhase = nil
                var cfg = llm.generation_defaults
                cfg.max_new_tokens = cap
                cfg.enable_thinking = false
                self.status = "generating…"

                for await chunk in llm.infer_stream(
                    prompt: promptText, config: cfg
                ) {
                    if chunk.is_final {
                        let tps = chunk.tokens_per_second ?? 0
                        self.statsLine = String(
                            format:
                                "%@ · %d tok · decode %.1f tok/s · TTFT %.0f ms · %@",
                            model.displayName,
                            chunk.generated_tokens ?? 0,
                            tps,
                            chunk.time_to_first_token * 1000,
                            chunk.stop_reason ?? ""
                        )
                        self.status = "done"
                        self.running = false
                    } else {
                        self.output += chunk.text
                    }
                }
            } catch {
                self.loadPhase = nil
                self.status = "error: \(error.localizedDescription)"
                self.running = false
            }
        }
    }

    // ----------------------------------------------------------------------------------
    // Benchmark (non-streaming, clean)
    // ----------------------------------------------------------------------------------
    func benchmark() {
        guard !running else { return }
        running = true
        output = ""
        statsLine = ""
        status = "preparing…"
        let model = selected
        let promptText = prompt
        let cap = maxNew
        let runCount = max(1, runs)

        Task {
            do {
                let llm = try await LLMHost.shared.llm(
                    for: model, onProgress: progressHandler()
                )
                self.loadPhase = nil
                var cfg = llm.generation_defaults
                // Fixed-length, deterministic decode so every run is comparable
                // and we don't measure a short EOS-terminated run.
                cfg.max_new_tokens = cap
                cfg.min_new_tokens = cap
                cfg.temperature = 0
                cfg.enable_thinking = false

                for w in 0 ..< Self.warmupRuns {
                    self.status = "warmup \(w + 1)/\(Self.warmupRuns)…"
                    _ = await Self.runInfer(llm, promptText, cfg)
                }

                var results: [LLMResult] = []
                for k in 0 ..< runCount {
                    self.status = "run \(k + 1)/\(runCount)…"
                    let r = await Self.runInfer(llm, promptText, cfg)
                    results.append(r)
                    if k < runCount - 1 {
                        try? await Task.sleep(
                            nanoseconds: Self.runCooldownNs
                        )
                    }
                }

                let row = Self.summarize(model: model, results: results)
                self.rows.removeAll { $0.model == model.displayName }
                self.rows.append(row)
                BenchSession.shared.add(.llm(
                    model: model.displayName,
                    prompt: promptText,
                    runs: runCount,
                    maxNewTokens: cap,
                    row: row,
                    perRunTokS: results.map(\.tokens_per_second)
                ))
                self.statsLine = String(
                    format: "%@ · best %.1f / median %.1f tok/s",
                    model.displayName, row.bestTokS, row.medianTokS
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

    // ----------------------------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------------------------
    // Run the synchronous SDK infer off the main actor — no @Published writes
    // happen during the decode loop, so the measurement is UI-free.
    private nonisolated static func runInfer(
        _ llm: TheStageLLM,
        _ prompt: String,
        _ cfg: LLMGenerationConfig
    ) async -> LLMResult {
        await Task.detached(priority: .userInitiated) {
            llm.infer(prompt: prompt, config: cfg)
        }.value
    }

    private static func summarize(
        model: BundledModel,
        results: [LLMResult]
    ) -> BenchRow {
        let tps = results.map(\.tokens_per_second).sorted()
        let predict = results.map(\.predict_ms_per_step)
        let host = results.map(\.host_ms_per_step)
        let ttft = results.map(\.time_to_first_token)
        return BenchRow(
            model: model.displayName,
            bestTokS: tps.last ?? 0,
            medianTokS: median(tps),
            meanTokS: mean(tps),
            predictMsStep: mean(predict),
            hostMsStep: mean(host),
            ttftMs: mean(ttft) * 1000,
            tokens: results.first?.generated_tokens ?? 0
        )
    }

    private static func mean(_ xs: [Double]) -> Double {
        xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
    }

    private static func median(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let m = sorted.count / 2
        return sorted.count % 2 == 0
            ? (sorted[m - 1] + sorted[m]) / 2
            : sorted[m]
    }
}

// --------------------------------------------------------------------------------------
// ContentView
// --------------------------------------------------------------------------------------
struct ContentView: View {
    @StateObject var model = BenchModel()
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("TheStage SDK · LLM bench")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                SessionShareButton()
            }
            .padding(.horizontal)

            Picker("Model", selection: $model.selected) {
                ForEach(ModelCatalog.all) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.running)
            .padding(.horizontal)

            TextField("Prompt", text: $model.prompt, axis: .vertical)
                .lineLimit(1 ... 4)
                .textFieldStyle(.roundedBorder)
                .focused($promptFocused)
                .disabled(model.running)
                .padding(.horizontal)

            HStack(spacing: 16) {
                Stepper("max \(model.maxNew)", value: $model.maxNew, in: 16 ... 1024, step: 16)
                Stepper("runs \(model.runs)", value: $model.runs, in: 1 ... 20)
            }
            .font(.system(.caption, design: .monospaced))
            .disabled(model.running)
            .padding(.horizontal)

            if let phase = model.loadPhase {
                VStack(alignment: .leading, spacing: 2) {
                    if phase == "loading" {
                        // Decrypt + CoreML compile: no granular progress
                        // exists (the SDK's next event is `ready`), so an
                        // indeterminate spinner beats a bar frozen at 85%.
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("loading (first run compiles the model)…")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ProgressView(value: model.loadFraction)
                        Text(String(
                            format: "%@ %.0f%%", phase, model.loadFraction * 100
                        ))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
            }

            HStack(spacing: 10) {
                Button {
                    promptFocused = false
                    model.generate()
                } label: {
                    label("Generate", color: .blue)
                }
                .disabled(model.running)

                Button {
                    promptFocused = false
                    model.benchmark()
                } label: {
                    label("Benchmark", color: .purple)
                }
                .disabled(model.running)
            }
            .padding(.horizontal)

            ScrollView {
                Text(model.output.isEmpty ? " " : model.output)
                    .font(.system(.body, design: .default))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal)

            if !model.rows.isEmpty {
                resultsCard
                    .padding(.horizontal)
            }

            Text(model.statsLine.isEmpty ? model.status : model.statsLine)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .padding(.top, 8)
    }

    private func label(_ title: String, color: Color) -> some View {
        Text(model.running ? "…" : title)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(model.running ? Color.gray : color)
            .foregroundColor(.white)
            .cornerRadius(10)
    }

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("decode tok/s (best / median / mean) · predict ms · host ms · TTFT ms")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            ForEach(model.rows) { r in
                Text(String(
                    format: "%@  %.1f/%.1f/%.1f  p%.2f h%.2f  ttft %.0f",
                    r.model.padding(toLength: 12, withPad: " ", startingAt: 0),
                    r.bestTokS, r.medianTokS, r.meanTokS,
                    r.predictMsStep, r.hostMsStep, r.ttftMs
                ))
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
    }
}

// --------------------------------------------------------------------------------------
// App entry
// --------------------------------------------------------------------------------------
@main
struct EngineBenchApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem { Label("LLM", systemImage: "text.bubble") }
                TTSBenchView()
                    .tabItem { Label("TTS", systemImage: "waveform") }
                ASRBenchView()
                    .tabItem { Label("ASR", systemImage: "mic") }
                VLMBenchView()
                    .tabItem { Label("VLM", systemImage: "camera") }
            }
        }
    }
}
