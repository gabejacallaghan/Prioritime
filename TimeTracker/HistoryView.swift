import SwiftUI

/// Every entry, grouped by day, newest first. Swipe to delete, tap to edit.
struct HistoryView: View {
    @EnvironmentObject private var store: DataStore
    @State private var editing: TimeEntry?

    private struct DayGroup: Identifiable {
        let day: Date
        let entries: [TimeEntry]
        var id: Date { day }
    }

    private var days: [DayGroup] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: store.entries) { cal.startOfDay(for: $0.date) }
        return grouped
            .map { DayGroup(day: $0.key, entries: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        List {
            if store.entries.isEmpty {
                Text("No entries yet. Logged time will show up here.")
                    .foregroundColor(.secondary)
            }
            ForEach(days) { group in
                Section {
                    ForEach(group.entries) { entry in
                        EntryRow(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture { editing = entry }
                            .swipeActions {
                                Button(role: .destructive) {
                                    store.deleteEntry(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text(dayTitle(group.day))
                        Spacer()
                        Text(TimeFormat.duration(group.entries.reduce(0) { $0 + $1.minutes }))
                    }
                }
            }
        }
        .navigationTitle("History")
        .sheet(item: $editing) { entry in
            EntryEditorView(entry: entry).environmentObject(store)
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

struct EntryEditorView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let original: TimeEntry
    @State private var activityID: UUID
    @State private var hours: Int
    @State private var minutes: Int
    @State private var date: Date
    @State private var note: String

    init(entry: TimeEntry) {
        original = entry
        _activityID = State(initialValue: entry.activityID)
        _hours = State(initialValue: min(entry.minutes / 60, 23))
        _minutes = State(initialValue: (entry.minutes % 60) / 5 * 5)
        _date = State(initialValue: entry.date)
        _note = State(initialValue: entry.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Activity", selection: $activityID) {
                    ForEach(store.activities) { a in
                        Label(a.name, systemImage: a.symbol).tag(a.id)
                    }
                }
                Section("Time spent") {
                    DurationWheelPicker(hours: $hours, minutes: $minutes)
                        .frame(height: 180)
                }
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                TextField("Note (optional)", text: $note)
                Section {
                    Button("Delete Entry", role: .destructive) {
                        store.deleteEntry(original)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = original
                        updated.activityID = activityID
                        updated.minutes = hours * 60 + minutes
                        updated.date = date
                        updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.updateEntry(updated)
                        dismiss()
                    }
                    .disabled(hours * 60 + minutes == 0)
                }
            }
        }
    }
}
