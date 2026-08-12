import Foundation
import TheStageSDK

@MainActor
final class TutorModel: ObservableObject {
    @Published var selected: TutorPhrase = TutorPhraseBook.all[0]
    @Published var status = "Load model, then Play"
    @Published var stats = ""
    @Published var taggedPreview = TutorPhraseBook.all[0].tagged
    @Published var running = false
    @Published var loading = false
    @Published var loaded = false
    @Published var loadFraction = 0.0
    @Published var loadPhase: String?

    private var tts: Qwen3TTSPipeline?
    private var player: StreamPlayer?
    private var playTask: Task<Void, Never>?

    private let model_name = "qwen3-tts-12hz-0.6b-base"
    private let hf_repo = "TheStageAI/Qwen3-TTS-12Hz-0.6B-Base"
    private let gap_ms = 250
    private let onset_ms = 25
    private let sample_rate = 24_000

    var phrases: [TutorPhrase] {
        TutorPhraseBook.all + [TutorPhraseBook.lesson]
    }

    func select(_ phrase: TutorPhrase) {
        guard !running else { return }
        selected = phrase
        taggedPreview = phrase.tagged
        stats = ""
        status = loaded ? "ready — \(phrase.title)" : "Load model, then Play"
    }

    /// Play uses the editable tagged script (dropdown only seeds it).
    private var script_to_play: String {
        let edited = taggedPreview.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return edited.isEmpty ? selected.tagged : taggedPreview
    }

    func load() {
        guard !loading, tts == nil else { return }
        loading = true
        status = "loading Qwen3-TTS…"
        loadFraction = 0
        Task {
            do {
                let token = (Bundle.main.object(forInfoDictionaryKey: "TSAPIToken")
                    as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                try await TheStageAI.shared.initialize(apiToken: token)

                let engines = Self.engines_path(
                    model_name: model_name, hf_repo: hf_repo
                )
                let first_pack = Self.voice_pack_path(tag: "en")
                // revision: nil → ModelRevisionMap (v1.1 .thestage), not
                // legacy engines.zip on `main`.
                let pipe = try await Qwen3TTSPipeline(
                    engines_path: engines,
                    voice_id: "b_ref",
                    voice_dir: first_pack,
                    language: "english",
                    device: "npu",
                    revision: nil,
                    on_load_progress: { [weak self] p in
                        Task { @MainActor [weak self] in
                            self?.loadFraction = p.fraction
                            self?.loadPhase = p.phase == .ready
                                ? nil : "\(p.phase)"
                        }
                    }
                )
                self.tts = pipe
                self.loadPhase = nil
                self.loading = false
                self.loaded = true
                self.status = "ready — pick a phrase"
            } catch {
                self.loading = false
                self.loadPhase = nil
                self.loaded = false
                self.status = "load error: \(error.localizedDescription)"
            }
        }
    }

    func play() {
        guard !running else { return }
        guard let tts else {
            status = "tap Load model first"
            return
        }
        running = true
        stats = ""
        status = "streaming…"
        let script = script_to_play
        playTask?.cancel()
        playTask = Task { await self.stream(script: script, tts: tts) }
    }

    func stop() {
        playTask?.cancel()
        playTask = nil
        player?.stop()
        player = nil
        running = false
        status = "stopped"
    }

    private func stream(script: String, tts: Qwen3TTSPipeline) async {
        defer {
            running = false
            playTask = nil
        }
        do {
            let segments = try LangTagParser.parse(script)
            player?.stop()
            let localPlayer = StreamPlayer(rate: Double(sample_rate))
            player = localPlayer
            let gap = [Float](
                repeating: 0, count: sample_rate * gap_ms / 1000
            )
            var total_samples = 0
            var first_ttfa: Double?
            let t_all = CFAbsoluteTimeGetCurrent()
            let splitter = NLSentenceSplitter()

            for (i, seg) in segments.enumerated() {
                if Task.isCancelled { break }
                let pack = Self.voice_pack_path(tag: seg.tag)
                try tts.set_voice(
                    voice_dir: pack, voice_id: "b_ref",
                    language: seg.qwen_language
                )
                status = "[\(i + 1)/\(segments.count)] \(seg.tag): \(seg.text)"

                var cfg = TTSGenerationConfig()
                cfg.seed = 42
                cfg.max_context_length = 256
                let n = seg.text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).count
                cfg.min_new_tokens = n <= 20 ? 14 : (n <= 40 ? 10 : 4)

                let t0 = CFAbsoluteTimeGetCurrent()
                var first = true
                let stream = tts.infer_stream(
                    text: seg.text,
                    config: cfg,
                    splitter: splitter,
                    stream_config: Qwen3TTSPipeline.recommended_stream_config
                )
                for await chunk in stream {
                    if Task.isCancelled { break }
                    guard var pcm = chunk.audio, !pcm.isEmpty else { continue }
                    if first_ttfa == nil {
                        first_ttfa = CFAbsoluteTimeGetCurrent() - t0
                    }
                    if first, onset_ms > 0 {
                        Self.fade_in(&pcm, ms: onset_ms, rate: sample_rate)
                        first = false
                    } else {
                        first = false
                    }
                    total_samples += pcm.count
                    localPlayer.enqueue(pcm)
                }
                if Task.isCancelled { break }
                if i + 1 < segments.count, !gap.isEmpty {
                    localPlayer.enqueue(gap)
                    total_samples += gap.count
                }
            }

            let audio_s = Double(total_samples) / Double(sample_rate)
            let wall = CFAbsoluteTimeGetCurrent() - t_all
            stats = String(
                format: "%.1fs audio · first TTFA %.2fs · wall %.1fs · %d spans",
                audio_s, first_ttfa ?? 0, wall, segments.count
            )
            // Wait only for leftover playback — not another full audio_s
            // (generation already covered most of realtime on device).
            if !Task.isCancelled {
                status = "playing…"
                await localPlayer.waitUntilDrained()
            }
            status = Task.isCancelled ? "stopped" : "done"
        } catch {
            status = "error: \(error.localizedDescription)"
        }
    }

    // MARK: - Paths

    private static func engines_path(model_name: String, hf_repo: String) -> String {
        if let dir = Bundle.main.resourceURL?
            .appendingPathComponent("BundledModels", isDirectory: true)
            .appendingPathComponent(model_name, isDirectory: true),
           FileManager.default.fileExists(atPath: dir.path)
        {
            return dir.path
        }
        return hf_repo
    }

    /// Prepared ICL pack folder shipped under VoicePacks/tutor_<tag>.
    static func voice_pack_path(tag: String) -> String? {
        let name = "tutor_\(tag.lowercased())"
        let roots: [URL?] = [
            Bundle.main.resourceURL?
                .appendingPathComponent("VoicePacks", isDirectory: true),
            Bundle.main.url(forResource: name, withExtension: nil,
                            subdirectory: "VoicePacks"),
        ]
        for root in roots {
            guard let root else { continue }
            let dir = root.path.hasSuffix(name)
                ? root
                : root.appendingPathComponent(name, isDirectory: true)
            let json = dir.appendingPathComponent("voice.json")
            if FileManager.default.fileExists(atPath: json.path) {
                return dir.path
            }
        }
        return nil
    }

    private static func fade_in(
        _ pcm: inout [Float], ms: Int, rate: Int
    ) {
        let n = min(pcm.count, rate * ms / 1000)
        guard n > 1 else { return }
        for i in 0..<n {
            pcm[i] *= Float(i) / Float(n - 1)
        }
    }
}
