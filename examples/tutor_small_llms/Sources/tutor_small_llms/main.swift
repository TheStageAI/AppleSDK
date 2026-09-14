// Start the SDK, load one pack, pick GUIDE / PACK.
import Foundation
import TheStageSDK

enum PackFamily {
    case lfm, qwen, gemma
}

struct Pack {
    let id: String
    let repo: String
    let family: PackFamily
}

let packs: [String: Pack] = [
    "lfm230": Pack(
        id: "lfm230", repo: "TheStageAI/LFM2.5-230M", family: .lfm
    ),
    "lfm350": Pack(
        id: "lfm350", repo: "TheStageAI/LFM2.5-350M", family: .lfm
    ),
    "qwen06": Pack(
        id: "qwen06", repo: "TheStageAI/Qwen3-0.6B", family: .qwen
    ),
    "gemma1b": Pack(
        id: "gemma1b", repo: "TheStageAI/gemma-3-1b-it", family: .gemma
    ),
]

func draw_progress(_ p: LoadProgress) {
    let width = 30
    let filled = max(0, min(width, Int((p.fraction * Double(width)).rounded())))
    let bar = String(repeating: "#", count: filled)
        + String(repeating: "-", count: width - filled)
    let pct = Int((p.fraction * 100).rounded())
    print("\r[\(p.model)] [\(bar)] \(pct)% \(p.phase.rawValue)        ",
          terminator: "")
    fflush(stdout)
}

// Line-buffer stdout so output survives redirection to a file.
setvbuf(stdout, nil, _IOLBF, 0)

let env = ProcessInfo.processInfo.environment
guard let token = env["TS_API_TOKEN"], !token.isEmpty else {
    FileHandle.standardError.write(Data(
        "Set TS_API_TOKEN in your environment first.\n".utf8))
    exit(1)
}

let pack_id = env["PACK"] ?? "lfm350"
guard let pack = packs[pack_id] else {
    FileHandle.standardError.write(Data(
        "PACK must be lfm230 | lfm350 | qwen06 | gemma1b\n".utf8))
    exit(1)
}

let guides = (env["GUIDE"] ?? "1,2,3,4,5")
    .split(separator: ",")
    .map { $0.trimmingCharacters(in: .whitespaces) }
    .filter { !$0.isEmpty }

let engines = env["LLM_BUNDLE"].flatMap { $0.isEmpty ? nil : $0 }
    ?? pack.repo
let device = env["LLM_DEVICE"] ?? "npu"

try await TheStageAI.shared.initialize(api_token: token)

let llm = try await TheStageLLM(
    engines_path: engines,
    device: device,
    max_context_size: 2048,
    on_load_progress: { draw_progress($0) }
)
print()
defer { llm.release() }

let llm_engine = LLMChatEngine(llm: llm)
print("pack=\(pack.id) path=\(engines) device=\(device) guides=\(guides.joined(separator: ","))")

for g in guides {
    switch g {
    case "1": try await run_guide_1(llm_engine: llm_engine, llm: llm)
    case "2": try await run_guide_2(llm_engine: llm_engine, llm: llm)
    case "3": try await run_guide_3(llm_engine: llm_engine, llm: llm)
    case "4": try await run_guide_4(llm_engine: llm_engine, llm: llm)
    case "5": try await run_guide_5(llm: llm, family: pack.family)
    default:
        FileHandle.standardError.write(Data(
            "unknown GUIDE \(g) — use 1..5\n".utf8))
        exit(1)
    }
}
