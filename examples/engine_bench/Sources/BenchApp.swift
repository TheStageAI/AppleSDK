// EngineBench — iPhone benchmark app driving the public SDK (TSLLM / TSVLM).
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
    /// Speculative decoding on packs that ship a proposer; ignored elsewhere.
    @Published var speculative = true
    @Published var runs = 5

    /// Dataset benchmark: `nil` = the prompt field (warmup + N runs of one
    /// prompt); otherwise a bundled prompt set, optionally one source, first
    /// `datasetLimit` rows. Only models with a matching tokenizer family list
    /// sets (``BundledModel/promptFamily``).
    @Published var datasetID: String?
    @Published var datasetSource: String?
    @Published var datasetLimit = 20

    var datasets: [PromptSet] { Self.setCache(for: selected) }
    var dataset: PromptSet? { datasets.first { $0.id == datasetID } }
    var datasetRows: [PromptRow] {
        guard let set = dataset else { return [] }
        return Array(set.rows(source: datasetSource).prefix(max(1, datasetLimit)))
    }

    private static var __sets: [String: [PromptSet]] = [:]
    private static func setCache(for model: BundledModel) -> [PromptSet] {
        guard let family = model.promptFamily else { return [] }
        if let hit = __sets[family] { return hit }
        let sets = PromptSetCatalog.sets(family: family)
        __sets[family] = sets
        return sets
    }

    /// Model-load progress (HF download / extract / decrypt+compile). `nil`
    /// when no load is in flight; fraction is monotonic 0...1 across phases.
    @Published var loadPhase: String?
    @Published var loadFraction = 0.0

    private static let warmupRuns = 2
    private static let runCooldownNs: UInt64 = 2_000_000_000

    /// Dev hook: launch argument `--autoload=<catalog name>` selects that
    /// model and starts Generate immediately (drives load bisects from the
    /// device log without taps). No-op when absent.
    init() {
        let args = ProcessInfo.processInfo.arguments
        guard let arg = args.first(where: { $0.hasPrefix("--autoload=") }),
            let m = ModelCatalog.all.first(where: {
                $0.name == String(arg.dropFirst("--autoload=".count))
            })
        else { return }
        selected = m
        Task { @MainActor [weak self] in self?.generate() }
    }

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
                Self.applyDecoding(&cfg, model, self.speculative)
                self.status = "generating…"

                for await chunk in try llm.infer_stream(
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
                        // Dev hook: `QLIP_GRAPH_PROFILE=1` in the environment
                        // prints the SDK's per-stage breakdown to stdout
                        // (readable via `devicectl ... launch --console`).
                        if ProcessInfo.processInfo.environment["QLIP_GRAPH_PROFILE"] != nil,
                            let report = llm.profile_report()
                        {
                            print("=== profile (\(model.displayName)) ===\n\(report)")
                        }
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
        if dataset != nil {
            datasetBenchmark()
            return
        }
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
                let useSpec = Self.applyDecoding(&cfg, model, self.speculative)
                let label = model.displayName
                    + (useSpec.map { $0 ? " · spec" : " · plain" } ?? "")

                for w in 0 ..< Self.warmupRuns {
                    self.status = "warmup \(w + 1)/\(Self.warmupRuns)…"
                    _ = try await Self.runInfer(llm, promptText, cfg)
                }

                var results: [LLMResult] = []
                for k in 0 ..< runCount {
                    self.status = "run \(k + 1)/\(runCount)…"
                    let r = try await Self.runInfer(llm, promptText, cfg)
                    results.append(r)
                    if k < runCount - 1 {
                        try? await Task.sleep(
                            nanoseconds: Self.runCooldownNs
                        )
                    }
                }

                let row = Self.summarize(label: label, results: results)
                self.rows.removeAll { $0.model == label }
                self.rows.append(row)
                BenchSession.shared.add(.llm(
                    model: label,
                    prompt: promptText,
                    runs: runCount,
                    maxNewTokens: cap,
                    row: row,
                    perRunTokS: results.map(\.tokens_per_second)
                ))
                let predicts = results.map(\.decode_predict_count)
                let accepted = predicts.last.map { p -> String in
                    p > 0 && (useSpec ?? false)
                        ? String(format: " · %.2f tok/predict", Double(cap) / Double(p)) : ""
                } ?? ""
                self.statsLine = String(
                    format: "%@ · best %.1f / median %.1f tok/s%@",
                    label, row.bestTokS, row.medianTokS, accepted
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
    // Dataset benchmark (bundled prompt sets)
    // ----------------------------------------------------------------------------------
    /// One untimed warmup per mode, then every selected prompt runs through
    /// `infer(prompt_ids:)` — natural EOS (no forced length), greedy on
    /// speculative packs, in the ONE mode the speculative switch selects.
    /// Decode tok/s is POOLED over the subset (sum(generated - 1) / sum(decode
    /// seconds)) with the per-prompt median beside it, plus tokens per verify
    /// cycle on the speculative run. Every row also lands in
    /// Documents/dataset_bench_<timestamp>.jsonl for pulling off the device.
    func datasetBenchmark() {
        guard !running, let set = dataset else { return }
        let rows = datasetRows
        guard !rows.isEmpty else { return }
        running = true
        output = ""
        statsLine = ""
        status = "preparing…"
        let model = selected
        let cap = maxNew
        let subset = "\(set.name)/\(datasetSource ?? "all") n=\(rows.count)"
        let modes: [Bool?] = [model.supportsSpeculation ? speculative : nil]

        Task {
            do {
                let llm = try await LLMHost.shared.llm(
                    for: model, onProgress: progressHandler()
                )
                self.loadPhase = nil
                func config(_ mode: Bool?) -> LLMGenerationConfig {
                    var cfg = llm.generation_defaults
                    cfg.max_new_tokens = cap
                    cfg.min_new_tokens = 0
                    cfg.enable_thinking = false
                    if let mode { Self.applyDecoding(&cfg, model, mode) } else {
                        cfg.temperature = 0
                    }
                    return cfg
                }
                for mode in modes {
                    self.status = "warmup \(Self.modeName(mode))…"
                    var warm = config(mode)
                    warm.max_new_tokens = 16
                    _ = try await Self.runInferIDs(llm, rows[0].prompt_ids, warm)
                }
                let stamp = ISO8601DateFormatter().string(from: Date())
                    .replacingOccurrences(of: ":", with: "-")
                let docs = FileManager.default.urls(
                    for: .documentDirectory, in: .userDomainMask)[0]
                let log = docs.appendingPathComponent("dataset_bench_\(stamp).jsonl")
                FileManager.default.createFile(atPath: log.path, contents: nil)
                let handle = try FileHandle(forWritingTo: log)
                defer { try? handle.close() }

                var results: [String: [(LLMResult, Double?)]] = [:]
                for (i, row) in rows.enumerated() {
                    var line: [String: Any] = [
                        "src": row.src, "id": row.id, "prompt_tokens": row.prompt_ids.count,
                    ]
                    for mode in modes {
                        self.status = "\(i + 1)/\(rows.count) \(Self.modeName(mode))…"
                        let r = try await Self.runInferIDs(llm, row.prompt_ids, config(mode))
                        let tpc = mode == true ? llm.spec_tokens_per_cycle : nil
                        results[Self.modeName(mode), default: []].append((r, tpc))
                        line[Self.modeName(mode)] = [
                            "generated": r.generated_tokens, "tok_s": r.tokens_per_second,
                            "decode_s": r.decode_seconds, "ttft_s": r.time_to_first_token,
                            "stop": r.stop_reason, "tokens_per_cycle": tpc ?? 0,
                        ] as [String: Any]
                    }
                    var data = try JSONSerialization.data(
                        withJSONObject: line, options: [.sortedKeys])
                    data.append(0x0A)
                    handle.write(data)
                }

                var parts: [String] = []
                for mode in modes {
                    let name = Self.modeName(mode)
                    let rs = results[name] ?? []
                    let label = "\(model.displayName) · \(subset) · \(name)"
                    let row = Self.summarizeDataset(label: label, results: rs.map(\.0))
                    self.rows.removeAll { $0.model == label }
                    self.rows.append(row)
                    BenchSession.shared.add(.llm(
                        model: label, prompt: "dataset \(set.id) \(datasetSource ?? "all")",
                        runs: rs.count, maxNewTokens: cap, row: row,
                        perRunTokS: rs.map(\.0.tokens_per_second)))
                    var part = String(format: "%@ %.1f tok/s", name, row.meanTokS)
                    let cycles = rs.compactMap(\.1)
                    if !cycles.isEmpty {
                        part += String(
                            format: " (%.2f tok/cycle)",
                            cycles.reduce(0, +) / Double(cycles.count))
                    }
                    parts.append(part)
                }
                let summary = "\(subset) · pooled " + parts.joined(separator: " · ")
                self.statsLine = summary
                self.output = summary + "\n\nper-prompt log: Documents/"
                    + log.lastPathComponent
                self.status = "done"
                self.running = false
            } catch {
                self.loadPhase = nil
                self.status = "error: \(error.localizedDescription)"
                self.running = false
            }
        }
    }

    private static func modeName(_ mode: Bool?) -> String {
        switch mode {
        case .some(true): return "spec"
        case .some(false): return "plain"
        case .none: return "default"
        }
    }

    private nonisolated static func runInferIDs(
        _ llm: any BenchTextModel, _ ids: [Int], _ cfg: LLMGenerationConfig
    ) async throws -> LLMResult {
        try await Task.detached(priority: .userInitiated) {
            try llm.infer(prompt_ids: ids, config: cfg)
        }.value
    }

    /// Dataset row: `mean` = POOLED decode tok/s over the subset, `median` =
    /// per-prompt median, `best` = per-prompt max; tokens = total generated.
    private static func summarizeDataset(label: String, results: [LLMResult]) -> BenchRow {
        let decode = results.reduce(0.0) { $0 + $1.decode_seconds }
        let generated = results.reduce(0) { $0 + max(0, $1.generated_tokens - 1) }
        let tps = results.map(\.tokens_per_second).sorted()
        return BenchRow(
            model: label,
            bestTokS: tps.last ?? 0,
            medianTokS: median(tps),
            meanTokS: decode > 0 ? Double(generated) / decode : 0,
            predictMsStep: mean(results.map(\.predict_ms_per_step)),
            hostMsStep: mean(results.map(\.host_ms_per_step)),
            ttftMs: mean(results.map(\.time_to_first_token)) * 1000,
            tokens: results.reduce(0) { $0 + $1.generated_tokens }
        )
    }

    // ----------------------------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------------------------
    /// `nil` = the pack's own policy (plain packs), an explicit switch on a
    /// speculative pack: `true` requires the proposer, `false` runs plain.
    private nonisolated static func decoding(_ model: BundledModel, _ on: Bool) -> Bool? {
        model.supportsSpeculation ? on : nil
    }

    /// Speculative decoding is greedy-only: the verifier compares argmax, so
    /// a pack's sampling defaults (temperature, repetition penalty) send the
    /// request to plain decoding whatever the switch says. On a speculative
    /// pack both switch positions therefore run the same greedy settings, so
    /// the on/off comparison measures the proposer and nothing else.
    @discardableResult
    private nonisolated static func applyDecoding(
        _ cfg: inout LLMGenerationConfig, _ model: BundledModel, _ on: Bool
    ) -> Bool? {
        let mode = decoding(model, on)
        if mode != nil {
            cfg.temperature = 0
            cfg.repetition_penalty = 1
        }
        cfg.speculative_decoding = mode
        return mode
    }

    // Run the synchronous SDK infer off the main actor — no @Published writes
    // happen during the decode loop, so the measurement is UI-free.
    private nonisolated static func runInfer(
        _ llm: any BenchTextModel,
        _ prompt: String,
        _ cfg: LLMGenerationConfig
    ) async throws -> LLMResult {
        try await Task.detached(priority: .userInitiated) {
            try llm.infer(prompt: prompt, config: cfg)
        }.value
    }

    private static func summarize(
        label: String,
        results: [LLMResult]
    ) -> BenchRow {
        let tps = results.map(\.tokens_per_second).sorted()
        let predict = results.map(\.predict_ms_per_step)
        let host = results.map(\.host_ms_per_step)
        let ttft = results.map(\.time_to_first_token)
        return BenchRow(
            model: label,
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

            // A menu picker, not a segmented one: a segmented control
            // divides the row between every option, so each label shrinks as
            // models are added and long names are cut to their first few
            // characters. The menu keeps the selected name readable at any
            // catalog size and shows every entry in full when opened.
            HStack(spacing: 12) {
                Text("Model")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Picker("Model", selection: $model.selected) {
                    ForEach(ModelCatalog.all) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
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

            Toggle("Speculative decoding", isOn: $model.speculative)
                .font(.system(.caption, design: .monospaced))
                .disabled(model.running || !model.selected.supportsSpeculation)
                .padding(.horizontal)

            if !model.datasets.isEmpty {
                datasetControls
                    .font(.system(.caption, design: .monospaced))
                    .disabled(model.running)
                    .padding(.horizontal)
            }

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

    /// Benchmark data: the prompt field or a bundled prompt set (source
    /// filter + first-N limit), run in the mode the speculative switch sets.
    private var datasetControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Benchmark data").foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Picker("Data", selection: $model.datasetID) {
                    Text("Prompt field").tag(String?.none)
                    ForEach(model.datasets) { set in
                        Text("\(set.name) (\(set.rows.count))").tag(Optional(set.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            if let set = model.dataset {
                HStack {
                    Text("Source").foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Picker("Source", selection: $model.datasetSource) {
                        Text("all (\(set.rows.count))").tag(String?.none)
                        ForEach(set.sources, id: \.self) { src in
                            Text("\(src) (\(set.rows(source: src).count))").tag(Optional(src))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                Stepper(
                    "first \(model.datasetRows.count) prompts",
                    value: $model.datasetLimit, in: 1 ... 400, step: 5)
            }
        }
        .onChange(of: model.selected) { _, _ in
            model.datasetID = nil
            model.datasetSource = nil
        }
        .onChange(of: model.datasetID) { _, _ in model.datasetSource = nil }
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
