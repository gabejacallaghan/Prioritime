import SwiftUI

/// One end-of-day reflection. There is at most one per calendar day.
struct CheckIn: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// Start of the day this check-in is about.
    var day: Date
    /// 1 (rough) ... 5 (great)
    var rating: Int
    var tags: [String] = []
    var note: String = ""
}

struct CheckInSettings: Codable, Equatable {
    var enabled = false
    var hour = 21
    var minute = 0
    var askForTags = true
    var askForNote = true
    var customTags: [String] = []
}

enum Mood {
    static let presetTags = [
        "happy", "alive", "grateful", "peaceful", "motivated", "proud",
        "tired", "stressed", "anxious", "sad", "lonely", "bored", "overwhelmed", "restless"
    ]

    static func emoji(_ rating: Int) -> String {
        switch rating {
        case 1: return "😞"
        case 2: return "🙁"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😄"
        default: return "·"
        }
    }

    static func label(_ rating: Int) -> String {
        switch rating {
        case 1: return "Rough"
        case 2: return "Low"
        case 3: return "Okay"
        case 4: return "Good"
        case 5: return "Great"
        default: return ""
        }
    }

    static func average(_ ratings: [Int]) -> Double {
        ratings.isEmpty ? 0 : Double(ratings.reduce(0, +)) / Double(ratings.count)
    }

    static func format(_ value: Double) -> String { String(format: "%.1f", value) }
}

// MARK: - Insights about mood

enum MoodInsights {
    static func insights(checkIns: [CheckIn],
                         allEntries: [TimeEntry],
                         activities: [Activity],
                         period: Period,
                         calendar: Calendar = .current) -> [Insight] {
        let current = checkIns.filter { period.contains($0.day) }
        guard !current.isEmpty else { return [] }

        var result: [Insight] = []
        let noun = period.kind.noun
        let avg = Mood.average(current.map(\.rating))
        let count = current.count

        result.append(Insight(symbol: "face.smiling", tint: .pink,
                              text: "You checked in \(count) \(count == 1 ? "time" : "times") this \(noun) and rated your days \(Mood.format(avg)) out of 5 on average."))

        // Compare with the previous period (needs a few check-ins on both sides to mean anything).
        let previous = Period(kind: period.kind, offset: -1,
                              now: period.interval.start.addingTimeInterval(1), calendar: calendar)
        let prev = checkIns.filter { previous.contains($0.day) }
        if prev.count >= 2 && count >= 2 {
            let prevAvg = Mood.average(prev.map(\.rating))
            let diff = avg - prevAvg
            if abs(diff) >= 0.3 {
                result.append(Insight(symbol: diff > 0 ? "arrow.up.right" : "arrow.down.right",
                                      tint: diff > 0 ? .green : .orange,
                                      text: "That's \(diff > 0 ? "higher" : "lower") than last \(noun) (\(Mood.format(prevAvg)))."))
            } else {
                result.append(Insight(symbol: "equal", tint: .secondary,
                                      text: "That's about the same as last \(noun) (\(Mood.format(prevAvg)))."))
            }
        }

        // Most common tag
        var tagCounts: [String: Int] = [:]
        for c in current { for t in c.tags { tagCounts[t, default: 0] += 1 } }
        if let top = tagCounts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }), top.value >= 2 {
            result.append(Insight(symbol: "tag", tint: .indigo,
                                  text: "The word you picked most was “\(top.key)”, on \(top.value) days."))
        }

        // Association between time on an activity and how the day was rated.
        // Uses all history because a single week is too small. This is correlation only.
        if let finding = strongestAssociation(checkIns: checkIns, allEntries: allEntries,
                                              activities: activities, calendar: calendar) {
            let (activity, withAvg, withoutAvg, withN, withoutN) = finding
            result.append(Insight(symbol: "link", tint: activity.color,
                                  text: "Across all your check-ins, days with 30+ minutes of \(activity.name) averaged \(Mood.format(withAvg)) vs \(Mood.format(withoutAvg)) on days without (\(withN) vs \(withoutN) days). That's a pattern in your data, not proof that one affects the other."))
        }
        return result
    }

    private static func strongestAssociation(checkIns: [CheckIn],
                                             allEntries: [TimeEntry],
                                             activities: [Activity],
                                             calendar: Calendar)
        -> (Activity, Double, Double, Int, Int)? {
        let byDay = Dictionary(grouping: allEntries) { calendar.startOfDay(for: $0.date) }
        var best: (Activity, Double, Double, Int, Int)?
        var bestGap = 0.0
        for activity in activities {
            var with: [Int] = []
            var without: [Int] = []
            for c in checkIns {
                let minutes = (byDay[c.day] ?? [])
                    .filter { $0.activityID == activity.id }
                    .reduce(0) { $0 + $1.minutes }
                if minutes >= 30 { with.append(c.rating) } else { without.append(c.rating) }
            }
            guard with.count >= 4, without.count >= 4 else { continue }
            let a = Mood.average(with), b = Mood.average(without)
            if abs(a - b) >= 0.7, abs(a - b) > bestGap {
                bestGap = abs(a - b)
                best = (activity, a, b, with.count, without.count)
            }
        }
        return best
    }
}
