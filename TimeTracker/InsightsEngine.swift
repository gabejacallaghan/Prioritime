import SwiftUI

struct Insight: Identifiable {
    let id = UUID()
    let symbol: String
    let tint: Color
    let text: String
}

/// Plain, factual observations about a period. Comparisons with the previous period
/// use the same elapsed span ("at this point last week") while the period is still
/// in progress, so a half-finished week is not compared to a full one.
enum InsightsEngine {
    static func insights(activities: [Activity],
                         allEntries: [TimeEntry],
                         period: Period,
                         now: Date = Date(),
                         calendar: Calendar = .current) -> [Insight] {
        let noun = period.kind.noun
        let current = allEntries.filter { period.contains($0.date) }
        let total = current.reduce(0) { $0 + $1.minutes }
        let ongoing = period.contains(now)

        guard total > 0 else {
            let text = ongoing
                ? "Nothing logged this \(noun) yet. Add time from the Log tab to see insights."
                : "Nothing was logged this \(noun)."
            return [Insight(symbol: "tray", tint: .secondary, text: text)]
        }

        var result: [Insight] = []
        var droppedIDs = Set<UUID>()
        let names = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0.name) })
        let currentTotals = totalsByActivity(current)
        let ranked = activities
            .map { ($0, currentTotals[$0.id] ?? 0) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }

        // 1. Most and least
        if let top = ranked.first {
            let share = Int((Double(top.1) / Double(total) * 100).rounded())
            result.append(Insight(symbol: "arrow.up.circle.fill", tint: top.0.color,
                                  text: "\(top.0.name) took the most time: \(TimeFormat.duration(top.1)), \(share)% of everything you logged."))
        }
        if ranked.count >= 2, let least = ranked.last {
            result.append(Insight(symbol: "arrow.down.circle.fill", tint: least.0.color,
                                  text: "\(least.0.name) got the least time of the activities you logged: \(TimeFormat.duration(least.1))."))
        }

        // 2. Compare with the previous period over the same elapsed span
        let previous = Period(kind: period.kind, offset: -1, now: period.interval.start.addingTimeInterval(1), calendar: calendar)
        let elapsed = ongoing ? now.timeIntervalSince(period.interval.start) : period.interval.duration
        let prevEnd = min(previous.interval.start.addingTimeInterval(elapsed), previous.interval.end)
        let prevEntries = allEntries.filter { $0.date >= previous.interval.start && $0.date < prevEnd }
        let prevTotal = prevEntries.reduce(0) { $0 + $1.minutes }
        let compareLabel = ongoing ? "at this point last \(noun)" : "last \(noun)"

        if prevTotal > 0 {
            let diff = total - prevTotal
            let pct = Int((Double(abs(diff)) / Double(prevTotal) * 100).rounded())
            let text: String
            if diff == 0 {
                text = "You've logged exactly as much time as \(compareLabel)."
            } else {
                let direction = diff > 0 ? "more" : "less"
                text = "You've logged \(TimeFormat.duration(diff)) \(direction) than \(compareLabel) (\(diff > 0 ? "+" : "−")\(pct)%)."
            }
            result.append(Insight(symbol: "chart.line.uptrend.xyaxis", tint: .accentColor, text: text))

            let prevTotals = totalsByActivity(prevEntries)
            let ids = Set(currentTotals.keys).union(prevTotals.keys).filter { names[$0] != nil }
            let diffs = ids.map { ($0, (currentTotals[$0] ?? 0) - (prevTotals[$0] ?? 0)) }

            if let up = diffs.filter({ $0.1 >= 30 }).max(by: { $0.1 < $1.1 }), let name = names[up.0] {
                result.append(Insight(symbol: "arrow.up.right", tint: .green,
                                      text: "\(name) is up \(TimeFormat.duration(up.1)) compared with \(compareLabel)."))
            }
            if let down = diffs.filter({ $0.1 <= -30 }).min(by: { $0.1 < $1.1 }), let name = names[down.0] {
                result.append(Insight(symbol: "arrow.down.right", tint: .orange,
                                      text: "\(name) is down \(TimeFormat.duration(down.1)) compared with \(compareLabel)."))
            }

            let dropped = activities.filter { (currentTotals[$0.id] ?? 0) == 0 && (prevTotals[$0.id] ?? 0) > 0 }
            droppedIDs = Set(dropped.map(\.id))
            if !dropped.isEmpty {
                result.append(Insight(symbol: "pause.circle", tint: .secondary,
                                      text: "No time on \(list(dropped.map(\.name))) \(ongoing ? "so far " : "")this \(noun), though you logged some \(compareLabel)."))
            }
        } else {
            result.append(Insight(symbol: "chart.line.uptrend.xyaxis", tint: .secondary,
                                  text: "Nothing was logged \(compareLabel), so there's no comparison yet."))
        }

        // 3. Daily pattern
        let byDay = Dictionary(grouping: current) { calendar.startOfDay(for: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.minutes } }
        let daysElapsed = max(1, daysBetween(period.interval.start, ongoing ? now : period.interval.end, calendar: calendar))
        if let busiest = byDay.max(by: { $0.value < $1.value }), byDay.count > 1 {
            let dayName = period.kind == .week
                ? busiest.key.formatted(.dateTime.weekday(.wide))
                : busiest.key.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            result.append(Insight(symbol: "calendar", tint: .purple,
                                  text: "Your busiest day was \(dayName) with \(TimeFormat.duration(busiest.value)). You averaged \(TimeFormat.duration(total / daysElapsed)) a day."))
        }

        // 4. Consistency
        let daysPerActivity = Dictionary(grouping: current, by: \.activityID)
            .mapValues { Set($0.map { calendar.startOfDay(for: $0.date) }).count }
        if let steady = daysPerActivity.max(by: { $0.value < $1.value }), steady.value >= 3, let name = names[steady.key] {
            result.append(Insight(symbol: "repeat", tint: .teal,
                                  text: "\(name) was the most consistent, logged on \(steady.value) of \(daysElapsed) days."))
        }

        // 5. Nothing logged at all
        let untouched = activities.filter { (currentTotals[$0.id] ?? 0) == 0 && !droppedIDs.contains($0.id) }
        if !untouched.isEmpty {
            result.append(Insight(symbol: "circle.dashed", tint: .secondary,
                                  text: "Nothing logged \(ongoing ? "yet " : "")for \(list(untouched.map(\.name)))."))
        }

        // 6. Reflection prompt
        if ranked.count >= 2 {
            result.append(Insight(symbol: "lightbulb", tint: .yellow,
                                  text: "Look at the ranking above. Does the order match what you consider most important?"))
        }
        return result
    }

    static func totalsByActivity(_ entries: [TimeEntry]) -> [UUID: Int] {
        entries.reduce(into: [:]) { $0[$1.activityID, default: 0] += $1.minutes }
    }

    private static func daysBetween(_ start: Date, _ end: Date, calendar: Calendar) -> Int {
        let s = calendar.startOfDay(for: start)
        let e = calendar.startOfDay(for: end.addingTimeInterval(-1))
        return (calendar.dateComponents([.day], from: s, to: e).day ?? 0) + 1
    }

    private static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + ", and " + names.last!
        }
    }
}
