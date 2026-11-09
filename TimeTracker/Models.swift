import SwiftUI

/// Something you spend time on (class, homework, prayer, ...).
struct Activity: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var colorIndex: Int
    var symbol: String

    var color: Color { Palette.color(colorIndex) }
}

/// One logged block of time.
struct TimeEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var activityID: UUID
    var minutes: Int
    var date: Date
    var note: String = ""
}

enum Palette {
    static let colors: [Color] = [
        .blue, .indigo, .purple, .pink, .red, .orange,
        .yellow, .green, .mint, .teal, .cyan, .brown, .gray
    ]

    static func color(_ index: Int) -> Color {
        let n = colors.count
        return colors[((index % n) + n) % n]
    }

    static let symbols: [String] = [
        "graduationcap", "book", "pencil", "laptopcomputer", "briefcase", "dollarsign.circle",
        "person.2", "cross", "heart", "figure.walk", "dumbbell", "bed.double",
        "fork.knife", "house", "cart", "car", "music.note", "paintbrush",
        "gamecontroller", "tv", "phone", "leaf", "sun.max", "star"
    ]
}

enum TimeFormat {
    /// 135 -> "2h 15m", 45 -> "45m", 120 -> "2h"
    static func duration(_ minutes: Int) -> String {
        let total = abs(minutes)
        let h = total / 60
        let m = total % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    /// 90 -> "1 hour 30 minutes"
    static func spoken(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        var parts: [String] = []
        if h > 0 { parts.append(h == 1 ? "1 hour" : "\(h) hours") }
        if m > 0 { parts.append("\(m) min") }
        return parts.isEmpty ? "0 min" : parts.joined(separator: " ")
    }
}

// MARK: - Periods

enum PeriodKind: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }
    var component: Calendar.Component { self == .week ? .weekOfYear : .month }
    var noun: String { self == .week ? "week" : "month" }
}

struct Period: Equatable {
    let kind: PeriodKind
    let interval: DateInterval

    /// offset 0 = the period containing `now`, -1 = the one before, etc.
    init(kind: PeriodKind, offset: Int, now: Date = Date(), calendar: Calendar = .current) {
        let anchor = calendar.date(byAdding: kind.component, value: offset, to: now) ?? now
        self.kind = kind
        self.interval = calendar.dateInterval(of: kind.component, for: anchor)
            ?? DateInterval(start: calendar.startOfDay(for: anchor), duration: 7 * 86_400)
    }

    func contains(_ date: Date) -> Bool {
        date >= interval.start && date < interval.end
    }

    var title: String {
        switch kind {
        case .month:
            return interval.start.formatted(.dateTime.month(.wide).year())
        case .week:
            let last = interval.end.addingTimeInterval(-1)
            let start = interval.start.formatted(.dateTime.month(.abbreviated).day())
            let end = last.formatted(.dateTime.month(.abbreviated).day().year())
            return "\(start) – \(end)"
        }
    }
}
