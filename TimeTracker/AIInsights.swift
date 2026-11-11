import Foundation
import Security

// MARK: - Keychain (the user's own Anthropic API key lives here, never in the JSON data file)

enum Keychain {
    private static let service = "com.gabejacallaghan.TimeTracker"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        delete(account)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - What gets sent

struct AIPayload {
    let text: String
    let dayCount: Int
    let entryCount: Int
    let checkInCount: Int
    let noteCount: Int

    /// Enough to say something meaningful about patterns.
    var hasEnoughData: Bool { dayCount >= 5 }
}

enum AIPayloadBuilder {
    static func build(activities: [Activity],
                      entries: [TimeEntry],
                      checkIns: [CheckIn],
                      days: Int,
                      includeNotes: Bool,
                      now: Date = Date(),
                      calendar: Calendar = .current) -> AIPayload {
        let end = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: end) ?? end

        let names = Dictionary(activities.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let windowEntries = entries.filter { $0.date >= start && $0.date < endExclusive && names[$0.activityID] != nil }
        let windowCheckIns = checkIns.filter { $0.day >= start && $0.day < endExclusive }

        let entriesByDay = Dictionary(grouping: windowEntries) { calendar.startOfDay(for: $0.date) }
        let checkInByDay = Dictionary(windowCheckIns.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        let allDays = Set(entriesByDay.keys).union(checkInByDay.keys).sorted()

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd EEE"

        var noteCount = 0
        var lines: [String] = []
        for day in allDays {
            var parts: [String] = []
            let dayEntries = entriesByDay[day] ?? []
            let perActivity = dayEntries.reduce(into: [UUID: Int]()) { $0[$1.activityID, default: 0] += $1.minutes }
            let timeText = perActivity
                .compactMap { id, minutes in names[id].map { ($0, minutes) } }
                .sorted { $0.1 > $1.1 }
                .map { "\($0.0) \(TimeFormat.duration($0.1))" }
            parts.append(timeText.isEmpty ? "time: nothing logged" : "time: " + timeText.joined(separator: ", "))

            if let c = checkInByDay[day] {
                parts.append("mood: \(c.rating)/5")
                if !c.tags.isEmpty { parts.append("feelings: " + c.tags.joined(separator: ", ")) }
                if includeNotes, !c.note.isEmpty {
                    parts.append("day note: \"\(clip(c.note))\"")
                    noteCount += 1
                }
            } else {
                parts.append("mood: no check-in")
            }

            if includeNotes {
                for e in dayEntries where !e.note.isEmpty {
                    if let name = names[e.activityID] {
                        parts.append("\(name) note: \"\(clip(e.note))\"")
                        noteCount += 1
                    }
                }
            }
            lines.append("\(formatter.string(from: day)) | " + parts.joined(separator: " | "))
        }

        // Totals computed here so the model doesn't have to add things up.
        let totals = Dictionary(grouping: windowEntries, by: \.activityID)
        let totalLines = activities.compactMap { a -> String? in
            guard let list = totals[a.id] else { return nil }
            let minutes = list.reduce(0) { $0 + $1.minutes }
            let activeDays = Set(list.map { calendar.startOfDay(for: $0.date) }).count
            return "- \(a.name): \(TimeFormat.duration(minutes)) total on \(activeDays) days"
        }
        let rated = windowCheckIns.map(\.rating)
        let moodLine = rated.isEmpty
            ? "No check-ins in this window."
            : "\(rated.count) check-ins, average mood \(Mood.format(Mood.average(rated)))/5."

        let text = """
        Window: \(formatter.string(from: start)) to \(formatter.string(from: end)) (\(days) days).
        Days that appear below had at least one time entry or check-in. Days that are missing had neither, \
        which usually means nothing was recorded, not that nothing happened.

        Activity totals:
        \(totalLines.isEmpty ? "- none" : totalLines.joined(separator: "\n"))

        Mood: \(moodLine)

        Day by day:
        \(lines.isEmpty ? "(no data)" : lines.joined(separator: "\n"))
        """

        return AIPayload(text: text, dayCount: allDays.count, entryCount: windowEntries.count,
                         checkInCount: windowCheckIns.count, noteCount: noteCount)
    }

    private static func clip(_ s: String) -> String {
        let flat = s.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 240 ? String(flat.prefix(240)) + "…" : flat
    }
}

// MARK: - API call (raw HTTP: there is no official Anthropic SDK for Swift)

enum AIInsightsError: LocalizedError {
    case invalidKey, rateLimited, refused, empty, network, server(String)

    var errorDescription: String? {
        switch self {
        case .invalidKey: return "Anthropic rejected the API key. Check that it's correct and has credit."
        case .rateLimited: return "Too many requests right now. Wait a minute and try again."
        case .refused: return "The model declined to analyze this data."
        case .empty: return "The response came back empty. Try again."
        case .network: return "Couldn't reach Anthropic. Check your connection and try again."
        case .server(let message): return "Something went wrong: \(message)"
        }
    }
}

enum AIInsightsService {
    static let model = "claude-opus-5-5"

    static let systemPrompt = """
    You help one person reflect on how they spend their time and how their days feel. You get a log of \
    time spent on activities they chose, plus optional end-of-day check-ins (a 1-5 rating, feeling tags, \
    and sometimes notes).

    Be honest rather than flattering. The goal is an accurate picture, not a comforting or a dramatic one.
    - Only report patterns the data supports. Give counts and sample sizes ("on 6 of 9 days") and say \
    plainly when data is too thin to conclude anything.
    - Keep observation separate from interpretation. For every association you mention, remember that \
    correlation is not causation: give at least one alternative explanation, including that the person may \
    simply have logged inconsistently.
    - Include findings that complicate a neat story or that the person may not want to hear, as well as \
    encouraging ones. Don't assume the person's current habits are good or bad.
    - Missing days are usually unrecorded days, not empty days.
    - The activities are the person's own priorities. Don't tell them what their priorities should be and \
    don't give moral, religious, medical or psychological advice or diagnoses. Ask reflective questions \
    instead.
    - If a note suggests serious distress or thoughts of self-harm, set the analysis aside, respond with \
    care, and encourage them to talk to someone they trust or a professional or crisis line.

    Format: plain text, under 350 words, with these short headings on their own lines: Patterns, What \
    stands out, Worth a closer look, Questions to reflect on. Use "-" bullets. Bold (**text**) is allowed \
    sparingly. No other markdown.
    """

    static func generate(data: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { throw AIInsightsError.network }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        // Lets the API re-run the request on a fallback model if a safety classifier declines it.
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "output_config": ["effort": "medium"],
            "fallbacks": "default",
            "system": systemPrompt,
            "messages": [[
                "role": "user",
                "content": "Here is my data. What patterns do you see?\n\n" + data
            ]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIInsightsError.network
        }

        guard let http = response as? HTTPURLResponse else { throw AIInsightsError.network }
        let json = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any]

        guard http.statusCode == 200 else {
            switch http.statusCode {
            case 401, 403: throw AIInsightsError.invalidKey
            case 429: throw AIInsightsError.rateLimited
            default:
                let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(http.statusCode)"
                throw AIInsightsError.server(message)
            }
        }

        // A refusal is an HTTP 200, so check the stop reason before reading content.
        if (json?["stop_reason"] as? String) == "refusal" { throw AIInsightsError.refused }

        let blocks = json?["content"] as? [[String: Any]] ?? []
        let text = blocks
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIInsightsError.empty }
        return text
    }
}
