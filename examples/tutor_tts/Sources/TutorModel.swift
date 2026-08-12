import Foundation
import TheStageSDK

// --------------------------------------------------------------------------------------
// TutorModel — load Qwen3-TTS, parse tagged script, stream PCM via AudioStreamPlayer
// --------------------------------------------------------------------------------------
/// Demo flow:
/// 1) Load HF / bundled Qwen3-TTS once.
/// 2) Parse the editable tagged script (`<en>…</en><es>…</es>` …).
/// 3) For each span: `set_voice` from ``VoicePacks/tutor_<tag>`` (clone identity),
///    then `infer_stream` the span text into ``AudioStreamPlayer``.
///
/// Voice packs are **not** the demo phrases — they only supply clone
/// `ref_text` / codes / embedding. Spoken lines live in ``TutorPhraseBook``.
@MainActor
final class TutorModel: ObservableObject {

    // ----------------------------------------------------------------------------------
    // Public Attributes (UI bindings)
    // ----------------------------------------------------------------------------------
    @Published var selected: TutorPhrase = TutorPhraseBook.all[0]
    @Published var status = "Load model, then Play"
    @Published var stats = ""
    @Published var taggedPreview = TutorPhraseBook.all[0].tagged
    @Published var running = false
    @Published var loading = false
    @Published var loaded = false
    @Published var loadFraction = 0.0
    @Published var loadPhase: String?

    var phrases: [TutorPhrase] {
        TutorPhraseBook.all + [TutorPhraseBook.lesson]
    }

    // ----------------------------------------------------------------------------------
    // Private Attributes
    // ----------------------------------------------------------------------------------
    private var __tts: Qwen3TTSPipeline?
    private var __player: AudioStreamPlayer?
    private var __play_task: Task<Void, Never>?

    private let __model_name = "qwen3-tts-12hz-0.6b-base"
    private let __hf_repo = "TheStageAI/Qwen3-TTS-12Hz-0.6B-Base"
    /// Silence inserted between language spans (ms).
    private let __gap_ms = 250
    /// Soft fade on the first PCM of each span (ms).
    private let __onset_ms = 25
    private let __sample_rate = 24_000

    /// Editable editor text wins; empty editor falls back to the picker phrase.
    private var __script_to_play: String {
        let edited = taggedPreview.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return edited.isEmpty ? selected.tagged : taggedPreview
    }

    // ----------------------------------------------------------------------------------
    // Public Methods
    // ----------------------------------------------------------------------------------
    func select(_ phrase: TutorPhrase) {
        guard !running else { return }
        selected = phrase
        taggedPreview = phrase.tagged
        stats = ""
        status = loaded ? "ready — \(phrase.title)" : "Load model, then Play"
    }

    func load() {
        guard !loading, __tts == nil else { return }
        loading = true
        status = "loading Qwen3-TTS…"
        loadFraction = 0
        Task { await __load_pipeline() }
    }

    func play() {
        guard !running else { return }
        guard let tts = __tts else {
            status = "tap Load model first"
            return
        }
        running = true
        stats = ""
        status = "streaming…"
        let script = __script_to_play
        __play_task?.cancel()
        __play_task = Task { await self.__stream(script: script, tts: tts) }
    }

    func stop() {
        __play_task?.cancel()
        __play_task = nil
        // Prefer flush over stop: AudioStreamPlayer.stop() deactivates
        // AVAudioSession on iOS and the next play can enqueue into a dead
        // graph (UI shows "playing…" with no audio).
        if let player = __player {
            player.flush()
        }
        running = false
        status = "stopped"
    }

    // ----------------------------------------------------------------------------------
    // Private Methods
    // ----------------------------------------------------------------------------------
    private func __load_pipeline() async {
        do {
            let token = (Bundle.main.object(forInfoDictionaryKey: "TSAPIToken")
                as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            try await TheStageAI.shared.initialize(apiToken: token)

            let engines = Self.__engines_path(
                model_name: __model_name, hf_repo: __hf_repo
            )
            // Seed voice from the English pack; each span calls set_voice again.
            let first_pack = Self.__voice_pack_path(tag: "en")
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
            __tts = pipe
            loadPhase = nil
            loading = false
            loaded = true
            status = "ready — pick a phrase"
        } catch {
            loading = false
            loadPhase = nil
            loaded = false
            status = "load error: \(error.localizedDescription)"
        }
    }

    /// Parse tags → set_voice per span → enqueue PCM on SDK AudioStreamPlayer.
    private func __stream(script: String, tts: Qwen3TTSPipeline) async {
        defer {
            running = false
            __play_task = nil
        }
        do {
            let segments = try LangTagParser.parse(script)
            // Reuse one player across plays. Tearing it down with stop()
            // deactivates AVAudioSession and the next turn goes silent.
            let player = __ensure_player()

            let gap = [Float](
                repeating: 0, count: __sample_rate * __gap_ms / 1000
            )
            var total_samples = 0
            var first_ttfa: Double?
            let t_all = CFAbsoluteTimeGetCurrent()

            for (i, seg) in segments.enumerated() {
                if Task.isCancelled { break }

                // Clone identity for this language (not the spoken phrase text).
                let pack = Self.__voice_pack_path(tag: seg.tag)
                try tts.set_voice(
                    voice_dir: pack,
                    voice_id: "b_ref",
                    language: seg.qwen_language
                )
                status =
                    "[\(i + 1)/\(segments.count)] \(seg.tag): \(seg.text)"

                var cfg = TTSGenerationConfig()
                cfg.seed = 42
                cfg.max_context_length = 256
                let n = seg.text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).count
                cfg.min_new_tokens = n <= 20 ? 14 : (n <= 40 ? 10 : 4)

                let t0 = CFAbsoluteTimeGetCurrent()
                var first_chunk = true
                // splitter defaults to NLSentenceSplitter()
                let stream = tts.infer_stream(
                    text: seg.text,
                    config: cfg,
                    stream_config: Qwen3TTSPipeline.recommended_stream_config
                )
                for await chunk in stream {
                    if Task.isCancelled { break }
                    guard var pcm = chunk.audio, !pcm.isEmpty else { continue }
                    if first_ttfa == nil {
                        first_ttfa = CFAbsoluteTimeGetCurrent() - t0
                    }
                    if first_chunk, __onset_ms > 0 {
                        Self.__fade_in(
                            &pcm, ms: __onset_ms, rate: __sample_rate
                        )
                    }
                    first_chunk = false
                    total_samples += pcm.count
                    player.enqueue(pcm)
                }
                if Task.isCancelled { break }

                if i + 1 < segments.count, !gap.isEmpty {
                    player.enqueue(gap)
                    total_samples += gap.count
                }
            }

            let audio_s = Double(total_samples) / Double(__sample_rate)
            let wall = CFAbsoluteTimeGetCurrent() - t_all
            stats = String(
                format:
                    "%.1fs audio · first TTFA %.2fs · wall %.1fs · %d spans",
                audio_s, first_ttfa ?? 0, wall, segments.count
            )

            // Drain leftover scheduled buffers (generation already ran realtime).
            // Keep the player alive afterward — do not stop()/setActive(false).
            if !Task.isCancelled {
                status = "playing…"
                await player.drain()
            }
            status = Task.isCancelled ? "stopped" : "done"
        } catch {
            status = "error: \(error.localizedDescription)"
        }
    }

    /// Live player for gapless PCM; flush leftovers, never tear down session
    /// between tutor turns.
    private func __ensure_player() -> AudioStreamPlayer {
        if let player = __player, player.is_playing {
            player.flush()
            return player
        }
        __player?.stop()
        let player = AudioStreamPlayer(sample_rate: Double(__sample_rate))
        player.start()
        __player = player
        return player
    }

    /// Bundled engines dir if present; otherwise HF repo id for download.
    private static func __engines_path(
        model_name: String, hf_repo: String
    ) -> String {
        if let dir = Bundle.main.resourceURL?
            .appendingPathComponent("BundledModels", isDirectory: true)
            .appendingPathComponent(model_name, isDirectory: true),
           FileManager.default.fileExists(atPath: dir.path)
        {
            return dir.path
        }
        return hf_repo
    }

    /// Prepared ICL pack folder: `VoicePacks/tutor_<tag>/voice.json`.
    /// Contains clone ref only — not the demo phrase book.
    private static func __voice_pack_path(tag: String) -> String? {
        let name = "tutor_\(tag.lowercased())"
        let roots: [URL?] = [
            Bundle.main.resourceURL?
                .appendingPathComponent("VoicePacks", isDirectory: true),
            Bundle.main.url(
                forResource: name,
                withExtension: nil,
                subdirectory: "VoicePacks"
            ),
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

    private static func __fade_in(
        _ pcm: inout [Float], ms: Int, rate: Int
    ) {
        let n = min(pcm.count, rate * ms / 1000)
        guard n > 1 else { return }
        for i in 0..<n {
            pcm[i] *= Float(i) / Float(n - 1)
        }
    }
}
