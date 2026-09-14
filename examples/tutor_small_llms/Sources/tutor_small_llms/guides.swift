// The five jobs: call the model, parse, allow-list, tools.
import Foundation
import TheStageSDK

enum ExtractionError: Error {
    case truncated
    case notFoundInInput
    case badJSON
}

struct Expense: Decodable {
    let merchant: String
    let total: Double
    let currency: String
    let date_printed: String
}

struct Meeting: Decodable {
    let title: String
    let day_said: String
    let start_said: String
    let end_said: String?
    let location: String?
}

struct MeetingWhen: Decodable {
    let title: String
    let when: String
    let location: String?
}

func greedy_config(_ llm: TheStageLLM, max_new_tokens: Int) -> LLMGenerationConfig {
    var config = llm.generation_defaults
    config.temperature = 0
    config.top_k = 0
    config.top_p = 1
    config.min_p = 0
    config.repetition_penalty = 1.0
    config.max_new_tokens = max_new_tokens
    config.enable_thinking = false
    return config
}

func vendor_config(_ llm: TheStageLLM, family: PackFamily) -> LLMGenerationConfig {
    var config = llm.generation_defaults
    config.enable_thinking = false
    config.max_new_tokens = 256
    switch family {
    case .lfm:
        config.temperature = 0.1
        config.top_k = 50
        config.top_p = 1.0
        config.min_p = 0.15
        config.repetition_penalty = 1.05
    case .qwen:
        config.temperature = 0.7
        config.top_k = 20
        config.top_p = 0.8
        config.min_p = 0
        config.repetition_penalty = 1.0
    case .gemma:
        config.temperature = 1.0
        config.top_k = 64
        config.top_p = 0.95
        config.min_p = 0
        config.repetition_penalty = 1.0
    }
    return config
}

func documented_tools() -> [Tool] {
    var weather = DefaultTools.get_weather
    weather.definition.description = """
        Current outdoor conditions and air temperature in °C at one \
        named place. This is live data: use it whenever a correct \
        answer depends on what the weather is like there now. Not \
        historical or multi-day forecast data. Argument: the place \
        the user named, in the form they said it. Returns a short \
        plain-text summary to paraphrase; do not read it out verbatim.
        """
    return [weather, DefaultTools.get_local_time, DefaultTools.web_search]
}

func run_guide_1(llm_engine: LLMChatEngine, llm: TheStageLLM) async throws {
    print("\n======== Guide 1 / Expense record ========")
    let config = greedy_config(llm, max_new_tokens: 128)
    try await expense_ticket(
        llm_engine: llm_engine, config: config,
        label: "ticket 1 — want 8.80 / 14/O8/2026",
        ocr: Recipes.starbucks_ocr
    )
    try await expense_ticket(
        llm_engine: llm_engine, config: config,
        label: "ticket 2 — want 7.70 / 02-09-2026",
        ocr: Recipes.tabaccheria_ocr
    )
}

private func expense_ticket(
    llm_engine: LLMChatEngine,
    config: LLMGenerationConfig,
    label: String,
    ocr: String
) async throws {
    print("-- \(label)")
    let result = try await llm_engine.infer(
        messages: [
            .user(Recipes.expense_shot_user),
            .assistant(Recipes.expense_shot_assistant),
            .user(ocr),
        ],
        system_prompt: Recipes.expense_system,
        tools: [],
        config: config
    )
    print(result.text)
    guard result.stop_reason != "max_new_tokens" else {
        print("  truncated — raise max_new_tokens")
        return
    }
    guard let expense = try? JSONDecoder().decode(
        Expense.self, from: Data(result.text.utf8)
    ) else {
        print("  (could not decode — extra keys or truncated JSON)")
        return
    }
    guard ocr.contains(expense.date_printed) else {
        print("  date_printed is not a verbatim copy of the ticket:", expense.date_printed)
        return
    }
    guard let day = normalize_printed_date(expense.date_printed) else {
        print("  could not normalise:", expense.date_printed)
        return
    }
    print(
        "  parsed:", expense.merchant, expense.total,
        iso_day(day)
    )
}

func run_guide_2(llm_engine: LLMChatEngine, llm: TheStageLLM) async throws {
    print("\n======== Guide 2 / Calendar event ========")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
    var today_parts = DateComponents()
    today_parts.year = 2026
    today_parts.month = 8
    today_parts.day = 13
    let today = calendar.date(from: today_parts)!

    let config = greedy_config(llm, max_new_tokens: 128)
    try await calendar_thread(
        llm_engine: llm_engine, config: config, calendar: calendar, today: today,
        label: "thread 1 — want 14/08 13:00 14:30",
        system: Recipes.calendar_system,
        shots: [
            (Recipes.calendar_shot_user, Recipes.calendar_shot_assistant),
        ],
        live: strip_export_prefixes(Recipes.marco_export)
    )
    try await calendar_thread(
        llm_engine: llm_engine, config: config, calendar: calendar, today: today,
        label: "thread 2 — when: tomorrow 18:30",
        system: Recipes.calendar_when_system,
        shots: Recipes.calendar_when_shots,
        live: Recipes.lena_revised
    )
}

private func calendar_thread(
    llm_engine: LLMChatEngine,
    config: LLMGenerationConfig,
    calendar: Calendar,
    today: Date,
    label: String,
    system: String,
    shots: [(String, String)],
    live: String
) async throws {
    print("-- \(label)")
    var messages: [ChatMessage] = []
    for (user, assistant) in shots {
        messages.append(.user(user))
        messages.append(.assistant(assistant))
    }
    messages.append(.user(live))
    let result = try await llm_engine.infer(
        messages: messages,
        system_prompt: system,
        tools: [],
        config: config
    )
    print(result.text)
    if let meeting = try? JSONDecoder().decode(
        MeetingWhen.self, from: Data(result.text.utf8)
    ), let start = parse_when(
        meeting.when, today: today, calendar: calendar
    ) {
        print("  parsed when:", meeting.when)
        print("  resolved start:", iso_stamp(start, calendar: calendar))
        return
    }
    guard let meeting = try? JSONDecoder().decode(
        Meeting.self, from: Data(result.text.utf8)
    ) else { return }
    if let start = resolve_said_datetime(
        day_said: meeting.day_said,
        start_said: meeting.start_said,
        today: today,
        calendar: calendar
    ) {
        print("  resolved start:", iso_stamp(start, calendar: calendar))
    }
}

func run_guide_3(llm_engine: LLMChatEngine, llm: TheStageLLM) async throws {
    print("\n======== Guide 3 / Pickup code ========")
    var config = greedy_config(llm, max_new_tokens: 16)
    config.max_new_tokens = 16
    let cases: [(String, String, String)] = [
        ("Amazon — want 482917", Recipes.sms_amazon, "482917"),
        ("InPost — want 730114", Recipes.sms_inpost, "730114"),
        ("Royal Mail — want 61529", Recipes.sms_royalmail, "61529"),
        ("Bring — want 4471-88", Recipes.sms_bring, "4471-88"),
    ]
    for (label, sms, want) in cases {
        print("-- \(label)")
        let result = try await llm_engine.infer(
            messages: [
                .user(Recipes.locker_shot_user),
                .assistant(Recipes.locker_shot_assistant),
                .user(sms),
            ],
            system_prompt: Recipes.locker_system,
            tools: [],
            config: config
        )
        let code = result.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        print(code)
        if sms.contains(code) && code == want {
            print("  ok")
        } else if sms.contains(code) {
            print("  in input, but not the expected token")
        } else {
            print("  not in input (few-shot parrot or sentence)")
        }
    }
}

func run_guide_4(llm_engine: LLMChatEngine, llm: TheStageLLM) async throws {
    print("\n======== Guide 4 / Share-sheet router ========")
    var config = greedy_config(llm, max_new_tokens: 16)
    config.max_new_tokens = 16
    let result = try await llm_engine.infer(
        messages: [
            .user(Recipes.router_shot_receipt), .assistant("receipt"),
            .user(Recipes.router_shot_event), .assistant("event"),
            .user(Recipes.sms_royalmail),
        ],
        system_prompt: Recipes.router_system,
        tools: [],
        config: config
    )
    let label = result.text.trimmingCharacters(
        in: .whitespacesAndNewlines
    )
    print(label)
    let allowed: Set<String> = ["receipt", "event", "locker", "other"]
    if !allowed.contains(label) {
        print("  not in allow-list")
    } else if label == "locker" {
        print("  ok")
    }
}

func run_guide_5(llm: TheStageLLM, family: PackFamily) async throws {
    print("\n======== Guide 5 / One live fact with a tool ========")
    guard llm.supports_tool_calling else {
        print("this pack cannot call tools (Gemma). skip.")
        return
    }
    let config = vendor_config(llm, family: family)
    let asks = [
        "What's the weather in Paris right now?",
        "What time is it in Tokyo?",
        "Thanks, that's all for now.",
    ]
    for ask in asks {
        print("-- \(ask)")
        let stream = try llm.infer_stream(
            prompt: ask,
            tools: documented_tools(),
            system_prompt: DefaultTools.voice_system_prompt,
            config: config
        )
        for await event in stream {
            switch event {
            case .text_delta(let text):
                print(text, terminator: "")
            case .tool_call(let call):
                print("\n  [tool_call] \(call.name)")
            default:
                break
            }
        }
        print()
    }
}
