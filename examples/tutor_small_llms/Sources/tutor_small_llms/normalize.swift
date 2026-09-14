// The deterministic half of the copy-verbatim recipes: the model copies what
// is printed or said; this code turns it into a Date. The checks for these
// functions live in benchmarks/tutor-small-llms/normalize_check.swift.
import Foundation

// MARK: - printed fiscal-ticket date -> ISO day

/// OCR on fiscal tickets swaps letters for digits inside numeric runs.
private func repair_ocr_digits(_ text: String) -> String {
    var out = ""
    for ch in text {
        switch ch {
        case "O", "o", "Q", "D": out.append("0")
        case "l", "I", "|": out.append("1")
        case "S": out.append("5")
        case "B": out.append("8")
        default: out.append(ch)
        }
    }
    return out
}

/// `14/O8/2026`, `03.11.25`, `02-09-2026` -> a day. Italian / German tickets
/// print day first; that is a locale fact the app knows.
func normalize_printed_date(
    _ printed: String,
    calendar: Calendar = Calendar(identifier: .gregorian)
) -> DateComponents? {
    // A faithful copy often carries the time too ("14/O8/2026 08:41").
    let day_field = repair_ocr_digits(printed)
        .split(separator: " ", omittingEmptySubsequences: true)
        .first
        .map(String.init) ?? ""
    let parts = day_field
        .split(whereSeparator: { "/.-".contains($0) })
        .map(String.init)
    guard parts.count == 3,
          let day = Int(parts[0]),
          let month = Int(parts[1]),
          var year = Int(parts[2])
    else { return nil }

    if parts[2].count == 2 { year += 2000 }
    guard (1...31).contains(day), (1...12).contains(month),
          (2000...2100).contains(year)
    else { return nil }

    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    guard let date = calendar.date(from: components),
          calendar.component(.day, from: date) == day
    else { return nil }
    return components
}

func iso_day(_ c: DateComponents) -> String {
    String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

func iso_stamp(_ date: Date, calendar: Calendar) -> String {
    let f = DateFormatter()
    f.calendar = calendar
    f.timeZone = calendar.timeZone
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return f.string(from: date)
}

// MARK: - chat export -> plain thread

/// Drop the `[dd/mm/yyyy, HH:mm:ss] ` bubble prefixes of a WhatsApp export
/// so the model never mistakes a send time for the meeting time.
func strip_export_prefixes(_ export: String) -> String {
    export
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line -> String in
            var s = Substring(line)
            if s.hasPrefix("["), let close = s.firstIndex(of: "]") {
                s = s[s.index(after: close)...]
                while s.hasPrefix(" ") { s = s.dropFirst() }
            }
            return String(s)
        }
        .joined(separator: "\n")
}

// MARK: - what the thread said -> event start

/// `14/08`, `tomorrow`, `friday` + `18:30` -> a concrete Date.
func resolve_said_datetime(
    day_said: String,
    start_said: String,
    today: Date,
    calendar: Calendar = Calendar(identifier: .gregorian)
) -> Date? {
    let time = start_said.split(separator: ":").map(String.init)
    guard time.count == 2, let hour = Int(time[0]), let minute = Int(time[1])
    else { return nil }

    let key = day_said.lowercased().trimmingCharacters(in: .whitespaces)
    var day_start: Date?

    if key == "today" || key == "oggi" || key == "heute" {
        day_start = calendar.startOfDay(for: today)
    } else if key == "tomorrow" || key == "domani" || key == "morgen" {
        day_start = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: today)
        )
    } else if let relative = relative_days(key) {
        day_start = calendar.date(
            byAdding: relative.unit, value: relative.count,
            to: calendar.startOfDay(for: today)
        )
    } else if let weekday = weekday_index(key) {
        day_start = next_weekday(weekday, from: today, calendar: calendar)
    } else {
        // dd/mm or dd/mm/yyyy as written in the body.
        let parts = key.split(whereSeparator: { "/.-".contains($0) })
            .map(String.init)
        if parts.count >= 2, let day = Int(parts[0]), let month = Int(parts[1]) {
            var components = DateComponents()
            components.day = day
            components.month = month
            components.year = parts.count > 2
                ? Int(parts[2]).map { $0 < 100 ? $0 + 2000 : $0 }
                : calendar.component(.year, from: today)
            day_start = calendar.date(from: components)
        }
    }

    guard let base = day_start else { return nil }
    return calendar.date(
        bySettingHour: hour, minute: minute, second: 0, of: base
    )
}

/// `tomorrow 18:30`, `in 3 days 10:00`, `14/08 13:00` -> a concrete Date.
func parse_when(_ when: String, today: Date, calendar: Calendar) -> Date? {
    let parts = when.split(separator: " ").map(String.init)
    guard parts.count >= 2, let clock = parts.last, clock.contains(":") else { return nil }
    let day = parts.dropLast().joined(separator: " ")
    return resolve_said_datetime(
        day_said: day, start_said: clock, today: today, calendar: calendar
    )
}

/// `in 3 days`, `in 2 weeks`, `in 5 months`.
private func relative_days(_ key: String) -> (unit: Calendar.Component, count: Int)? {
    let words = key.split(separator: " ").map(String.init)
    guard words.count == 3, words[0] == "in", let n = Int(words[1]) else { return nil }
    switch words[2] {
    case "day", "days": return (.day, n)
    case "week", "weeks": return (.weekOfYear, n)
    case "month", "months": return (.month, n)
    default: return nil
    }
}

private func weekday_index(_ name: String) -> Int? {
    let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    if let i = names.firstIndex(of: name) { return i + 1 }
    let short = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    if let i = short.firstIndex(of: name) { return i + 1 }
    return nil
}

private func next_weekday(_ weekday: Int, from today: Date, calendar: Calendar) -> Date? {
    var components = DateComponents()
    components.weekday = weekday
    return calendar.nextDate(
        after: calendar.startOfDay(for: today).addingTimeInterval(-1),
        matching: components,
        matchingPolicy: .nextTime
    )
}
