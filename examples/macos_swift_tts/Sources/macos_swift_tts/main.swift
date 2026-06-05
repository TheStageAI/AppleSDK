import Foundation
import TheStageSDK

// Draw the load as a single bar that redraws in place. `fraction` is
// monotonic across the whole load (download -> extract -> load -> ready),
// and the handler fires often, so we use `\r` instead of a new line per
// call — otherwise the download alone floods the terminal.
func draw_progress(_ p: LoadProgress) {
    let width = 30
    let filled = max(0, min(width, Int((p.fraction * Double(width)).rounded())))
    let bar = String(repeating: "#", count: filled)
        + String(repeating: "-", count: width - filled)
    let pct = Int((p.fraction * 100).rounded())
    // Trailing spaces pad over the previous (longer) phase label.
    print("\r[\(p.model)] [\(bar)] \(pct)% \(p.phase.rawValue)        ",
          terminator: "")
    fflush(stdout)
}

// 1. API token from the environment: `export TS_API_TOKEN=th_...`
guard let token = ProcessInfo.processInfo.environment["TS_API_TOKEN"],
      !token.isEmpty else {
    FileHandle.standardError.write(Data(
        "Set TS_API_TOKEN in your environment first.\n".utf8))
    exit(1)
}

// 2. Initialize the SDK (validated once, then runs offline).
try await TheStageAI.shared.initialize(apiToken: token)

// 3. Load the multilingual NeuTTS model from HuggingFace. The handler
//    fires through downloading -> extracting -> loading -> ready;
//    downloading/extracting are skipped once the engines are cached.
let tts = try await NeuTTSMultilingualPipeline(
    engines_path: "TheStageAI/neutts-multilingual",
    voice_id: "paul",
    language: "english",
    revision: "develop",
    on_load_progress: { draw_progress($0) }
)
print()  // finish the in-place progress line

// 4. Warm up once. The first synthesis after load pays a one-time cost
//    (Metal kernel compilation, lazy graph build), so its tokens/sec is
//    misleadingly low. Run a throwaway phrase now — and discard it — so
//    the user's first real synthesis, and the metrics below, reflect
//    steady-state speed.
print("warming up...")
let warmup_start = CFAbsoluteTimeGetCurrent()
_ = tts.infer(text: "Warm up.")
print(String(format: "warmed up in %.2fs",
             CFAbsoluteTimeGetCurrent() - warmup_start))

// 5. Play audio chunks as they stream in. The player runs at the
//    pipeline's own rate (24 kHz for NeuTTS) — read it, never hardcode.
print("output sample rate: \(tts.sample_rate) Hz")
let player = AudioStreamPlayer(sample_rate: Double(tts.sample_rate))
player.start()

let streamer = tts.open_streamer()
let consumer = Task {
    for await chunk in streamer.output {
        // The stream tags each chunk with its rate. If it ever disagreed
        // with the player, playback would sound sped up / slowed down —
        // so assert they match instead of trusting a constant.
        if let sr = chunk.sample_rate, sr != tts.sample_rate {
            print("WARNING: chunk rate \(sr) != player rate \(tts.sample_rate)")
        }
        if let pcm = chunk.audio, !pcm.isEmpty { player.enqueue(pcm) }
        // The final chunk carries no audio, just the run's metrics.
        if chunk.is_final {
            let ttfa = chunk.time_to_first_token ?? 0
            let tps = chunk.tokens_per_second ?? 0
            let total = chunk.total_seconds ?? 0
            let toks = chunk.generated_tokens ?? 0
            print("metrics: first audio \(String(format: "%.2f", ttfa))s, "
                + "\(toks) tokens, \(String(format: "%.1f", tps)) tok/s, "
                + "\(String(format: "%.2f", total))s total")
        }
    }
}

// 6. Speak a couple of phrases; audio starts before the last finishes.
let phrases = [
    "Hey — who's the prettiest one here? It's you. You're the best, you know it, and nobody can ever take that away from you.",
    "Don't let your dreams be dreams. Just do it.",
]
for phrase in phrases {
    print("speaking: \(phrase)")
    streamer.send(phrase + " ")
}
streamer.stop_stream()

// 7. Wait for playback to finish, then tear down.
await consumer.value
await player.drain()
player.stop()
print("Done.")
