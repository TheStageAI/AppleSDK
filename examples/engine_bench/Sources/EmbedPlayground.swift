import AVFoundation
import CoreTransferable
import PhotosUI
import SwiftUI
import TheStageSDK
import UniformTypeIdentifiers

// --------------------------------------------------------------------------------------
// Embed playground — try EmbeddingGemma 2 on text, images, audio and video
// --------------------------------------------------------------------------------------
/// A collection of embedded items of any modality. One item is the anchor (a
/// tapped item, or the search query); every other item shows its cosine
/// similarity to the anchor and the list is sorted by it, so the same screen
/// covers "compare A with B" and cross-modal retrieval.
@MainActor
final class EmbedPlaygroundModel: ObservableObject {

    struct Item: Identifiable {
        let id = UUID()
        let kind: String
        let label: String
        let thumbnail: UIImage?
        let result: EmbeddingResult
        let ms: Double
    }

    /// What the banner at the top shows.
    enum Phase: Equatable {
        case idle
        case working(String)
        case done(String)
        case failed(String)
    }

    @Published var items: [Item] = []
    @Published var anchor: Item?
    @Published var phase: Phase = .idle
    @Published var model_ready = false
    @Published var busy = false
    @Published var recording = false
    @Published var record_seconds: Double = 0
    /// The item added last, highlighted for a moment in the list.
    @Published var last_added: UUID?

    private var pipeline: EmbeddingPipeline?
    private var open_task: Task<EmbeddingPipeline, Error>?
    private var input_engine: AudioInputEngine?
    private var capture_task: Task<Void, Never>?
    private var captured: [Float] = []

    private static let repo = "TheStageAI/embeddinggemma-2"
    private static let max_record_seconds = 30

    // -- ranking -------------------------------------------------------------------------

    /// Items other than the anchor with their cosine to it, best first.
    var ranked: [(item: Item, cosine: Float?)] {
        guard let anchor else { return items.map { ($0, nil) } }
        return items.filter { $0.id != anchor.id }
            .map { ($0, try? EmbeddingPipeline.similarity(anchor.result, $0.result)) }
            .sorted { ($0.cosine ?? -2) > ($1.cosine ?? -2) }
    }

    /// Opens the pack ahead of the first input so that input is not slowed by loading.
    func preload() {
        guard pipeline == nil, open_task == nil else { return }
        Task {
            do {
                _ = try await __open()
                if case .working = phase { phase = .idle }
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func select(_ item: Item) {
        anchor = anchor?.id == item.id ? nil : item
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        if anchor?.id == item.id { anchor = nil }
    }

    // -- inputs --------------------------------------------------------------------------

    /// Adds a text item; `as_anchor` makes it the search query.
    func add_text(_ text: String, task: EmbeddingTask, as_anchor: Bool) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        __embed(kind: "text · \(task.rawValue)", label: text, thumbnail: nil,
                as_anchor: as_anchor) { try await $0.infer(text: text, task: task) }
    }

    func add_image(_ data: Data) {
        guard let ui = UIImage(data: data), let cg = Self.__upright(ui) else {
            phase = .failed("Could not decode the picked image")
            return
        }
        __embed(kind: "image", label: "\(cg.width)×\(cg.height)", thumbnail: UIImage(cgImage: cg),
                as_anchor: false) { try await $0.infer(image: cg) }
    }

    func add_video(_ url: URL) {
        let thumb = Self.__video_thumbnail(url)
        __embed(kind: "video", label: url.lastPathComponent, thumbnail: thumb,
                as_anchor: false) { try await $0.infer(video: url, max_frames: nil) }
    }

    func add_audio_file(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let (samples, rate) = Self.__read_mono(url) else {
            phase = .failed("Could not read \(url.lastPathComponent)")
            return
        }
        __add_audio(samples, rate: rate, label: url.lastPathComponent)
    }

    func toggle_record() {
        recording ? __stop_record() : __start_record()
    }

    // -- private -------------------------------------------------------------------------

    private func __add_audio(_ samples: [Float], rate: Int, label: String) {
        let secs = Double(samples.count) / Double(rate)
        __embed(kind: "audio", label: String(format: "%@ · %.1f s", label, secs), thumbnail: nil,
                as_anchor: false) { try await $0.infer(audio: samples, sample_rate: rate) }
    }

    private func __embed(
        kind: String, label: String, thumbnail: UIImage?, as_anchor: Bool,
        _ run: @escaping @Sendable (EmbeddingPipeline) async throws -> EmbeddingResult
    ) {
        guard !busy else {
            phase = .failed("Still working on the previous input, try again in a moment")
            return
        }
        busy = true
        Task {
            do {
                let pipeline = try await __open()
                phase = .working("Embedding \(kind)…")
                let t0 = Date()
                let result = try await Task.detached { try await run(pipeline) }.value
                let ms = Date().timeIntervalSince(t0) * 1000
                let item = Item(kind: kind, label: label, thumbnail: thumbnail, result: result, ms: ms)
                items.insert(item, at: 0)
                if as_anchor { anchor = item }
                last_added = item.id
                phase = .done(String(format: "%@ %@ in %.0f ms (%d tokens%@)",
                                     as_anchor ? "Searching with" : "Added", kind, ms,
                                     result.token_count, result.truncated ? ", truncated" : ""))
            } catch {
                phase = .failed(error.localizedDescription)
            }
            busy = false
        }
    }

    /// One shared open: the preload and the first input await the same task;
    /// a failed open is retried by the next input.
    private func __open() async throws -> EmbeddingPipeline {
        if let pipeline { return pipeline }
        if open_task == nil {
            phase = .working("Loading EmbeddingGemma 2…")
            let repo = Self.repo
            open_task = Task {
                try await LLMHost.shared.ensureInitialized()
                let bundled = Bundle.main.resourceURL?
                    .appendingPathComponent("BundledModels/embeddinggemma-2", isDirectory: true)
                let path = bundled.map { FileManager.default.fileExists(atPath: $0.path) } == true
                    ? bundled!.path : repo
                return try await EmbeddingPipeline(engines_path: path)
            }
        }
        do {
            let opened = try await open_task!.value
            pipeline = opened
            model_ready = true
            return opened
        } catch {
            open_task = nil
            throw error
        }
    }

    private func __start_record() {
        guard !busy else { return }
        captured = []
        do {
            var cfg = AudioInputConfig()
            cfg.sample_rate = 16000
            cfg.channels = 1
            let engine = AudioInputEngine(config: cfg)
            try engine.start()
            input_engine = engine
            recording = true
            record_seconds = 0
            phase = .working("Recording… tap Stop when done")
            capture_task = Task { [weak self] in
                for await chunk in engine.stream {
                    guard let self else { return }
                    await MainActor.run {
                        self.captured.append(contentsOf: chunk)
                        self.record_seconds = Double(self.captured.count) / 16000
                        if self.captured.count >= Self.max_record_seconds * 16000 {
                            self.__stop_record()
                        }
                    }
                }
            }
        } catch {
            phase = .failed("Microphone: \(error.localizedDescription)")
        }
    }

    private func __stop_record() {
        guard recording else { return }
        recording = false
        capture_task?.cancel()
        capture_task = nil
        input_engine?.stop()
        input_engine = nil
        let audio = captured
        captured = []
        guard audio.count > 1600 else {
            phase = .failed("Recording too short")
            return
        }
        __add_audio(audio, rate: 16000, label: "mic")
    }

    /// Redraws the image so EXIF orientation is applied to the pixels.
    private static func __upright(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage { return cg }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format)
            .image { _ in image.draw(at: .zero) }.cgImage
    }

    private static func __video_thumbnail(_ url: URL) -> UIImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        return (try? gen.copyCGImage(at: .zero, actualTime: nil)).map(UIImage.init(cgImage:))
    }

    /// Mono float samples (channels averaged) at the file's own rate.
    private static func __read_mono(_ url: URL) -> ([Float], Int)? {
        guard let file = try? AVAudioFile(forReading: url),
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32, sampleRate: file.processingFormat.sampleRate,
                  channels: file.processingFormat.channelCount, interleaved: false),
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buf)) != nil,
              let data = buf.floatChannelData
        else { return nil }
        let n = Int(buf.frameLength)
        let channels = Int(format.channelCount)
        var mono = [Float](repeating: 0, count: n)
        for c in 0..<channels {
            for i in 0..<n { mono[i] += data[c][i] / Float(channels) }
        }
        return (mono, Int(format.sampleRate))
    }
}

// --------------------------------------------------------------------------------------
// Picker transfer types
// --------------------------------------------------------------------------------------
/// A picked video copied into the app's temporary directory.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let dst = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "." + received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: dst)
            return PickedMovie(url: dst)
        }
    }
}

// --------------------------------------------------------------------------------------
// EmbedPlaygroundView
// --------------------------------------------------------------------------------------
struct EmbedPlaygroundView: View {
    @StateObject private var model = EmbedPlaygroundModel()
    @State private var query = ""
    @State private var image_pick: PhotosPickerItem?
    @State private var video_pick: PhotosPickerItem?
    @State private var importing_audio = false
    @State private var adding_text = false
    @State private var new_text = ""
    @State private var new_text_task: EmbeddingTask = .DOCUMENT

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    banner
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Describe what you look for…", text: $query)
                            .submitLabel(.search)
                            .onSubmit(search)
                        Button("Search", action: search)
                            .buttonStyle(.borderedProminent)
                            .disabled(model.busy || query.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Search the collection with text")
                } footer: {
                    Text("Ranks every item below by cosine similarity to the query.")
                }

                Section("Add to the collection") {
                    LazyVGrid(columns: columns, spacing: 10) {
                        PhotosPicker(selection: $image_pick, matching: .images) {
                            tile("Photo", "photo.on.rectangle")
                        }
                        PhotosPicker(selection: $video_pick, matching: .videos) {
                            tile("Video", "film")
                        }
                        Button { adding_text = true } label: { tile("Text", "text.quote") }
                        Button { importing_audio = true } label: { tile("Audio file", "waveform") }
                        Button { model.toggle_record() } label: {
                            tile(model.recording ? String(format: "Stop %.0fs", model.record_seconds)
                                                 : "Record",
                                 model.recording ? "stop.circle.fill" : "mic.fill",
                                 tint: model.recording ? .red : .accentColor)
                        }
                        .disabled(model.busy && !model.recording)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy && !model.recording)
                    .padding(.vertical, 4)
                }

                if let anchor = model.anchor {
                    Section {
                        row(anchor, cosine: nil)
                    } header: {
                        HStack {
                            Text("Compared with")
                            Spacer()
                            Button("Clear") { model.anchor = nil }.font(.caption)
                        }
                    }
                }

                Section {
                    if model.items.isEmpty {
                        Text("Nothing here yet. Add a photo, video, text or audio above.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.ranked, id: \.item.id) { entry in
                        row(entry.item, cosine: entry.cosine)
                            .id(entry.item.id)
                            .swipeActions {
                                Button("Delete", role: .destructive) { model.remove(entry.item) }
                            }
                    }
                } header: {
                    Text(model.anchor == nil
                         ? "Collection (\(model.items.count)) · tap an item to compare"
                         : "Most similar first")
                } footer: {
                    if model.anchor != nil {
                        Text("Compare the order, not the absolute value: unrelated pairs score about 0.5-0.6 with this model, good matches about 0.65-0.75.")
                    }
                }
            }
            .animation(.default, value: model.items.map(\.id))
            .animation(.default, value: model.anchor?.id)
            .onChange(of: model.last_added) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    if model.last_added == id { model.last_added = nil }
                }
            }
        }
        .onAppear { model.preload() }
        .onChange(of: image_pick) { _, pick in
            guard let pick else { return }
            model.phase = .working("Reading the photo…")
            Task {
                if let data = try? await pick.loadTransferable(type: Data.self) {
                    model.add_image(data)
                } else {
                    model.phase = .failed("Could not read the picked photo")
                }
                image_pick = nil
            }
        }
        .onChange(of: video_pick) { _, pick in
            guard let pick else { return }
            model.phase = .working("Reading the video…")
            Task {
                if let movie = try? await pick.loadTransferable(type: PickedMovie.self) {
                    model.add_video(movie.url)
                } else {
                    model.phase = .failed("Could not read the picked video")
                }
                video_pick = nil
            }
        }
        .fileImporter(isPresented: $importing_audio, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url): model.add_audio_file(url)
            case .failure(let error): model.phase = .failed(error.localizedDescription)
            }
        }
        .sheet(isPresented: $adding_text) { text_sheet }
    }

    // -- pieces --------------------------------------------------------------------------

    private func search() {
        model.add_text(query, task: .QUERY, as_anchor: true)
    }

    /// Model state and the result of the last action, always visible at the top.
    @ViewBuilder
    private var banner: some View {
        let (icon, text, color, spinning): (String, String, Color, Bool) = {
            switch model.phase {
            case .idle:
                return model.model_ready
                    ? ("checkmark.circle.fill", "EmbeddingGemma 2 ready", .green, false)
                    : ("hourglass", "Loading EmbeddingGemma 2…", .secondary, true)
            case .working(let m): return ("hourglass", m, .accentColor, true)
            case .done(let m): return ("checkmark.circle.fill", m, .green, false)
            case .failed(let m): return ("exclamationmark.triangle.fill", m, .red, false)
            }
        }()
        HStack(spacing: 10) {
            if spinning {
                ProgressView()
            } else {
                Image(systemName: icon).foregroundStyle(color)
            }
            Text(text).font(.subheadline).foregroundStyle(color == .secondary ? .secondary : .primary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private func tile(_ title: String, _ icon: String, tint: Color = .accentColor) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2)
            Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }

    private var text_sheet: some View {
        NavigationStack {
            Form {
                TextField("A caption, a sentence or a document", text: $new_text, axis: .vertical)
                    .lineLimit(3...8)
                Picker("Embed as", selection: $new_text_task) {
                    Text("document").tag(EmbeddingTask.DOCUMENT)
                    Text("query").tag(EmbeddingTask.QUERY)
                }
                .pickerStyle(.segmented)
            }
            .navigationTitle("Add text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding_text = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        model.add_text(new_text, task: new_text_task, as_anchor: false)
                        new_text = ""
                        adding_text = false
                    }
                    .disabled(new_text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private func row(_ item: EmbedPlaygroundModel.Item, cosine: Float?) -> some View {
        let is_anchor = model.anchor?.id == item.id
        Button { model.select(item) } label: {
            HStack(spacing: 12) {
                Group {
                    if let thumb = item.thumbnail {
                        Image(uiImage: thumb).resizable().scaledToFill()
                    } else {
                        Image(systemName: item.kind.hasPrefix("audio") ? "waveform" : "text.quote")
                            .font(.title3).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.secondary.opacity(0.1))
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.label).lineLimit(2)
                    Text(String(format: "%@ · %.0f ms", item.kind, item.ms))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let cosine {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.3f", cosine))
                            .font(.system(.body, design: .monospaced)).bold()
                            .foregroundStyle(__color(cosine))
                        Text("cosine").font(.caption2).foregroundStyle(.secondary)
                    }
                } else if is_anchor {
                    Image(systemName: "scope").foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            model.last_added == item.id ? Color.green.opacity(0.18)
                : is_anchor ? Color.accentColor.opacity(0.12) : nil
        )
    }

    /// EmbeddingGemma 2 is anisotropic: unrelated pairs already score 0.5-0.6
    /// and good matches 0.65-0.75, so the colour is relative to the shown
    /// items: the top third green, the middle orange, the rest grey.
    private func __color(_ c: Float) -> Color {
        let cs = model.ranked.compactMap(\.cosine)
        guard let lo = cs.min(), let hi = cs.max(), hi - lo > 1e-4 else { return .primary }
        let t = (c - lo) / (hi - lo)
        return t >= 0.67 ? .green : t >= 0.34 ? .orange : .secondary
    }
}
