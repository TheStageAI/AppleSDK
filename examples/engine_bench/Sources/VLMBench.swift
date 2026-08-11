import PhotosUI
import SwiftUI
import TheStageSDK
import UIKit

// --------------------------------------------------------------------------------------
// VLM catalog
// --------------------------------------------------------------------------------------
struct BundledVLMModel: Identifiable, Hashable {
    let name: String
    let displayName: String
    let hfRepo: String
    /// Optional HF revision override. `nil` → ``ModelRevisionMap``.
    let revision: String?

    var id: String { name }

    func enginesPath() -> String {
        let dir = Bundle.main.resourceURL?
            .appendingPathComponent("BundledModels", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        if let dir, FileManager.default.fileExists(atPath: dir.path) {
            return dir.path
        }
        return hfRepo
    }

    var isBundled: Bool {
        let dir = Bundle.main.resourceURL?
            .appendingPathComponent("BundledModels", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        return dir.map {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false
    }
}

enum VLMCatalog {
    static let all: [BundledVLMModel] = [
        BundledVLMModel(
            name: "lfm2.5-vl-450m",
            displayName: "LFM2.5-VL 450M",
            hfRepo: "TheStageAI/LFM2.5-VL-450M",
            revision: nil
        ),
    ]
    static var first: BundledVLMModel { all[0] }
}

// --------------------------------------------------------------------------------------
// VLMHost — one-slot pipeline cache
// --------------------------------------------------------------------------------------
@MainActor
final class VLMHost {
    static let shared = VLMHost()
    private init() {}

    private var current: (key: String, vlm: TheStageVLM)?

    func pipeline(
        for model: BundledVLMModel,
        onProgress: LoadProgressHandler? = nil
    ) async throws -> TheStageVLM {
        try await LLMHost.shared.ensureInitialized()
        if let current, current.key == model.name {
            return current.vlm
        }
        current?.vlm.release()
        current = nil
        let vlm = try await TheStageVLM(
            engines_path: model.enginesPath(),
            device: "npu",
            revision: model.revision,
            on_load_progress: onProgress
        )
        current = (model.name, vlm)
        return vlm
    }

    func release() {
        current?.vlm.release()
        current = nil
    }
}

// --------------------------------------------------------------------------------------
// VLMBenchRow
// --------------------------------------------------------------------------------------
struct VLMBenchRow: Identifiable {
    let id = UUID()
    let model: String
    let bestTokS: Double
    let medianTokS: Double
    let meanTokS: Double
    let medianEncodeMs: Double
    let medianPrefillMs: Double
    let medianTotalMs: Double
    let tokens: Int
}

// --------------------------------------------------------------------------------------
// VLMBenchModel
// --------------------------------------------------------------------------------------
@MainActor
final class VLMBenchModel: ObservableObject {
    @Published var selected: BundledVLMModel = VLMCatalog.first
    @Published var prompt = "Describe this image briefly."
    @Published var output = ""
    @Published var statsLine = ""
    @Published var status = "pick an image, then Generate"
    @Published var rows: [VLMBenchRow] = []
    @Published var running = false
    @Published var maxNew = 64
    @Published var runs = 5
    @Published var preview: UIImage?
    @Published var loadPhase: String?
    @Published var loadFraction = 0.0

    private var cgImage: CGImage?
    private static let warmupRuns = 1

    private func progressHandler() -> LoadProgressHandler {
        { [weak self] p in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.loadFraction = p.fraction
                self.loadPhase = p.phase == .ready ? nil : "\(p.phase)"
            }
        }
    }

    func setImage(_ image: UIImage) {
        preview = image
        cgImage = image.fixedOrientationCGImage()
        status = "image ready — tap Generate or Benchmark"
    }

    func clearImage() {
        preview = nil
        cgImage = nil
        status = "pick an image, then Generate"
    }

    // ----------------------------------------------------------------------------------
    // Generate (streaming — same UX as LLM tab)
    // ----------------------------------------------------------------------------------
    func generate() {
        guard !running else { return }
        guard let cgImage else {
            status = "pick a camera / gallery image first"
            return
        }
        running = true
        output = ""
        statsLine = ""
        status = "loading \(selected.displayName)…"
        let model = selected
        let promptText = prompt
        let cap = maxNew
        let image = cgImage

        Task {
            do {
                let vlm = try await VLMHost.shared.pipeline(
                    for: model, onProgress: progressHandler()
                )
                self.loadPhase = nil
                var cfg = vlm.generation_defaults
                cfg.max_new_tokens = cap
                cfg.temperature = 0
                // encode + fuse run before the AsyncStream yields; then
                // deltas match TheStageLLM.infer_stream (LLMStreamChunk).
                self.status = "encoding…"
                let stream = try vlm.infer_stream(
                    images: [image],
                    prompt: promptText,
                    config: cfg
                )
                self.status = "generating…"
                for await chunk in stream {
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
        guard let cgImage else {
            status = "pick a camera / gallery image first"
            return
        }
        running = true
        output = ""
        statsLine = ""
        status = "loading \(selected.displayName)…"
        let model = selected
        let promptText = prompt
        let cap = maxNew
        let n = runs
        let image = cgImage

        Task {
            do {
                let vlm = try await VLMHost.shared.pipeline(
                    for: model, onProgress: progressHandler()
                )
                self.loadPhase = nil
                var cfg = vlm.generation_defaults
                cfg.max_new_tokens = cap
                cfg.temperature = 0
                status = "warmup + \(n) quiet runs…"

                let warm = Self.warmupRuns
                let measured = try await Task.detached(priority: .userInitiated) {
                    () -> (
                        tok: [Double], enc: [Double], pre: [Double],
                        tot: [Double], tokens: Int, text: String
                    ) in
                    for _ in 0..<warm {
                        _ = try vlm.infer(
                            images: [image], prompt: promptText, config: cfg
                        )
                    }
                    var tokS: [Double] = []
                    var encS: [Double] = []
                    var preS: [Double] = []
                    var totS: [Double] = []
                    var lastText = ""
                    var lastTokens = 0
                    for _ in 0..<n {
                        let r = try vlm.infer(
                            images: [image], prompt: promptText, config: cfg
                        )
                        tokS.append(r.tokens_per_second)
                        encS.append(r.encode_seconds)
                        preS.append(r.prefill_seconds)
                        totS.append(r.total_seconds)
                        lastText = r.text
                        lastTokens = r.generated_tokens
                    }
                    return (tokS, encS, preS, totS, lastTokens, lastText)
                }.value

                let row = VLMBenchRow(
                    model: model.displayName,
                    bestTokS: measured.tok.max() ?? 0,
                    medianTokS: Self.median(measured.tok) ?? 0,
                    meanTokS: measured.tok.reduce(0, +)
                        / Double(max(measured.tok.count, 1)),
                    medianEncodeMs: (Self.median(measured.enc) ?? 0) * 1000,
                    medianPrefillMs: (Self.median(measured.pre) ?? 0) * 1000,
                    medianTotalMs: (Self.median(measured.tot) ?? 0) * 1000,
                    tokens: measured.tokens
                )
                self.rows.removeAll { $0.model == model.displayName }
                self.rows.insert(row, at: 0)
                self.output = measured.text
                self.statsLine = String(
                    format: "%@ · best %.1f / median %.1f tok/s · enc %.0f ms",
                    model.displayName, row.bestTokS, row.medianTokS,
                    row.medianEncodeMs
                )
                BenchSession.shared.add(
                    .vlm(
                        model: model.displayName,
                        prompt: promptText,
                        runs: n,
                        maxNewTokens: cap,
                        row: row,
                        perRunTokS: measured.tok,
                        perRunEncodeMs: measured.enc.map { $0 * 1000 }
                    )
                )
                self.status = "done"
            } catch {
                self.status = "error: \(error.localizedDescription)"
            }
            self.running = false
        }
    }

    private static func median(_ xs: [Double]) -> Double? {
        let s = xs.sorted()
        guard !s.isEmpty else { return nil }
        let mid = s.count / 2
        if s.count % 2 == 0 {
            return (s[mid - 1] + s[mid]) / 2
        }
        return s[mid]
    }
}

// --------------------------------------------------------------------------------------
// UIImage orientation helper
// --------------------------------------------------------------------------------------
private extension UIImage {
    func fixedOrientationCGImage() -> CGImage? {
        if imageOrientation == .up { return cgImage }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let normalized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return normalized.cgImage
    }
}

// --------------------------------------------------------------------------------------
// VLMBenchView — LLM-tab layout + image strip
// --------------------------------------------------------------------------------------
struct VLMBenchView: View {
    @StateObject private var model = VLMBenchModel()
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("TheStage SDK · VLM bench")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                SessionShareButton()
            }
            .padding(.horizontal)

            Picker("Model", selection: $model.selected) {
                ForEach(VLMCatalog.all) { m in
                    Text(
                        m.isBundled
                            ? "\(m.displayName) (bundled)"
                            : m.displayName
                    ).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.running)
            .padding(.horizontal)

            // Compact image strip (not a full-bleed hero — keeps output
            // space for streaming text, matching the LLM tab).
            HStack(spacing: 10) {
                if let preview = model.preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                model.clearImage()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.55))
                            }
                            .offset(x: 6, y: -6)
                            .disabled(model.running)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 72, height: 72)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Gallery", systemImage: "photo")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.running)

                        Button {
                            showCamera = true
                        } label: {
                            Label("Camera", systemImage: "camera")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.running)
                    }
                    Text(
                        model.preview == nil
                            ? "Choose a photo to caption"
                            : "Image ready"
                    )
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            TextField("Prompt", text: $model.prompt, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($promptFocused)
                .disabled(model.running)
                .padding(.horizontal)

            HStack(spacing: 16) {
                Stepper(
                    "max \(model.maxNew)",
                    value: $model.maxNew, in: 16...256, step: 16
                )
                Stepper(
                    "runs \(model.runs)",
                    value: $model.runs, in: 1...20
                )
            }
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
                    actionLabel("Generate", color: .blue)
                }
                .disabled(model.running)

                Button {
                    promptFocused = false
                    model.benchmark()
                } label: {
                    actionLabel("Benchmark", color: .purple)
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
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data)
                {
                    model.setImage(ui)
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                if let image { model.setImage(image) }
                showCamera = false
            }
            .ignoresSafeArea()
        }
    }

    private func actionLabel(_ title: String, color: Color) -> some View {
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
            Text("tok/s best/med/mean · enc · prefill · total")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            ForEach(model.rows) { r in
                Text(String(
                    format: "%@  %.1f/%.1f/%.1f  e%.0f p%.0f t%.0f",
                    r.model,
                    r.bestTokS, r.medianTokS, r.meanTokS,
                    r.medianEncodeMs, r.medianPrefillMs,
                    r.medianTotalMs
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
// CameraPicker — UIImagePickerController wrapper
// --------------------------------------------------------------------------------------
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera)
            ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController, context: Context
    ) {}

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    final class Coordinator: NSObject, UINavigationControllerDelegate,
        UIImagePickerControllerDelegate
    {
        let onImage: (UIImage?) -> Void
        init(onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }

        func imagePickerControllerDidCancel(
            _ picker: UIImagePickerController
        ) {
            onImage(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onImage(info[.originalImage] as? UIImage)
        }
    }
}
