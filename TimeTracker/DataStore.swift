import Foundation
import SwiftUI

/// Holds all activities and entries and persists them as JSON in the app's Documents folder.
final class DataStore: ObservableObject {
    @Published private(set) var activities: [Activity] = []
    @Published private(set) var entries: [TimeEntry] = []
    @Published private(set) var checkIns: [CheckIn] = []
    @Published private(set) var checkInSettings = CheckInSettings()

    private struct SaveFile: Codable {
        var activities: [Activity]
        var entries: [TimeEntry]
        // Optional so files saved before check-ins existed still load.
        var checkIns: [CheckIn]?
        var checkInSettings: CheckInSettings?
    }

    private let fileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("timetracker.json")
        load()
    }

    // MARK: Activities

    func activity(with id: UUID) -> Activity? {
        activities.first { $0.id == id }
    }

    func addActivity(_ activity: Activity) {
        activities.append(activity)
        save()
    }

    func updateActivity(_ activity: Activity) {
        guard let i = activities.firstIndex(where: { $0.id == activity.id }) else { return }
        activities[i] = activity
        save()
    }

    /// Deletes the activity and every entry logged for it.
    func deleteActivity(_ activity: Activity) {
        activities.removeAll { $0.id == activity.id }
        entries.removeAll { $0.activityID == activity.id }
        save()
    }

    func moveActivities(from source: IndexSet, to destination: Int) {
        activities.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func entryCount(for activity: Activity) -> Int {
        entries.filter { $0.activityID == activity.id }.count
    }

    func isNameTaken(_ name: String, excluding id: UUID?) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return activities.contains { $0.id != id && $0.name.lowercased() == trimmed }
    }

    // MARK: Entries

    func addEntry(_ entry: TimeEntry) {
        entries.append(entry)
        save()
    }

    func updateEntry(_ entry: TimeEntry) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[i] = entry
        save()
    }

    func deleteEntry(_ entry: TimeEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func entries(in interval: DateInterval) -> [TimeEntry] {
        entries.filter { $0.date >= interval.start && $0.date < interval.end }
    }

    func entries(from start: Date, to end: Date) -> [TimeEntry] {
        entries.filter { $0.date >= start && $0.date < end }
    }

    // MARK: Check-ins

    func checkIn(on day: Date) -> CheckIn? {
        let start = Calendar.current.startOfDay(for: day)
        return checkIns.first { $0.day == start }
    }

    /// One check-in per day: saving again replaces the earlier one.
    func saveCheckIn(day: Date, rating: Int, tags: [String], note: String) {
        let start = Calendar.current.startOfDay(for: day)
        if let i = checkIns.firstIndex(where: { $0.day == start }) {
            checkIns[i].rating = rating
            checkIns[i].tags = tags
            checkIns[i].note = note
        } else {
            checkIns.append(CheckIn(day: start, rating: rating, tags: tags, note: note))
        }
        save()
    }

    func deleteCheckIn(_ checkIn: CheckIn) {
        checkIns.removeAll { $0.id == checkIn.id }
        save()
    }

    func updateCheckInSettings(_ settings: CheckInSettings) {
        checkInSettings = settings
        save()
    }

    /// Adds a user-made tag and returns its stored form, or nil if it was empty.
    func addCustomTag(_ raw: String) -> String? {
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !tag.isEmpty else { return nil }
        let known = Mood.presetTags + checkInSettings.customTags
        if !known.contains(tag) {
            checkInSettings.customTags.append(tag)
            save()
        }
        return tag
    }

    // MARK: Persistence

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let file = try? JSONDecoder().decode(SaveFile.self, from: data) {
            activities = file.activities
            entries = file.entries
            checkIns = file.checkIns ?? []
            checkInSettings = file.checkInSettings ?? CheckInSettings()
        } else {
            activities = Self.defaultActivities
            entries = []
            save()
        }
    }

    private func save() {
        let file = SaveFile(activities: activities, entries: entries,
                            checkIns: checkIns, checkInSettings: checkInSettings)
        do {
            let data = try JSONEncoder().encode(file)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("TimeTracker save failed: \(error)")
        }
    }

    static let defaultActivities: [Activity] = [
        Activity(name: "Class", colorIndex: 0, symbol: "graduationcap"),
        Activity(name: "Homework", colorIndex: 2, symbol: "pencil"),
        Activity(name: "Paid Work", colorIndex: 7, symbol: "briefcase"),
        Activity(name: "Social Time", colorIndex: 5, symbol: "person.2"),
        Activity(name: "Prayer", colorIndex: 1, symbol: "cross"),
        Activity(name: "Exercise", colorIndex: 4, symbol: "figure.walk")
    ]
}
