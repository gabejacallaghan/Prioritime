import SwiftUI

/// Home screen: pick an activity, spin the wheels, tap Log.
struct LogView: View {
    @EnvironmentObject private var store: DataStore

    @State private var selectedActivityID: UUID?
    @State private var hours = 0
    @State private var minutes = 0
    @State private var date = Date()
    @State private var note = ""
    @State private var showingNewActivity = false
    @State private var toast: String?
    @State private var editingEntry: TimeEntry?

    private var totalMinutes: Int { hours * 60 + minutes }
    private var selectedActivity: Activity? {
        guard let id = selectedActivityID else { return nil }
        return store.activity(with: id)
    }
    private var canSave: Bool { selectedActivity != nil && totalMinutes > 0 }

    private var todaysEntries: [TimeEntry] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        return store.entries(from: start, to: end).sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    activitySection
                    durationSection
                    detailsSection
                    saveButton
                    todaySection
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Time Tracker")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("History")
                }
            }
            .overlay(alignment: .top) { toastView }
            .sheet(isPresented: $showingNewActivity) {
                ActivityEditorView(activity: nil) { newActivity in
                    selectedActivityID = newActivity.id
                }
                .environmentObject(store)
            }
            .sheet(item: $editingEntry) { entry in
                EntryEditorView(entry: entry).environmentObject(store)
            }
            .onAppear {
                if selectedActivity == nil { selectedActivityID = store.activities.first?.id }
            }
        }
    }

    // MARK: Sections

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Activity")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                ForEach(store.activities) { activity in
                    ActivityChip(activity: activity, isSelected: activity.id == selectedActivityID) {
                        withAnimation(.easeOut(duration: 0.15)) { selectedActivityID = activity.id }
                    }
                }
                Button {
                    showingNewActivity = true
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundColor(.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundColor(.secondary.opacity(0.5))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Time spent")
            DurationWheelPicker(hours: $hours, minutes: $minutes)
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var detailsSection: some View {
        VStack(spacing: 0) {
            DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                .padding(.horizontal)
                .padding(.vertical, 8)
            Divider().padding(.leading)
            TextField("Note (optional)", text: $note)
                .padding(.horizontal)
                .padding(.vertical, 12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(saveTitle)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(canSave ? (selectedActivity?.color ?? .accentColor) : Color.gray.opacity(0.4))
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
    }

    private var saveTitle: String {
        guard let activity = selectedActivity else { return "Choose an activity" }
        guard totalMinutes > 0 else { return "Set a time" }
        return "Log \(TimeFormat.duration(totalMinutes)) of \(activity.name)"
    }

    @ViewBuilder
    private var todaySection: some View {
        let entries = todaysEntries
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel("Today")
                    Spacer()
                    Text(TimeFormat.duration(entries.reduce(0) { $0 + $1.minutes }))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        EntryRow(entry: entry)
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                            .onTapGesture { editingEntry = entry }
                            .contextMenu {
                                Button { editingEntry = entry } label: { Label("Edit", systemImage: "pencil") }
                                Button(role: .destructive) {
                                    withAnimation { store.deleteEntry(entry) }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        if index < entries.count - 1 { Divider().padding(.leading, 56) }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = toast {
            Label(toast, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: Actions

    private func save() {
        guard let activity = selectedActivity, totalMinutes > 0 else { return }
        // Keep the time of day for today; for past dates use noon so it never slips across midnight.
        let cal = Calendar.current
        let stamp: Date
        if cal.isDateInToday(date) {
            stamp = Date()
        } else {
            stamp = cal.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        }
        store.addEntry(TimeEntry(activityID: activity.id, minutes: totalMinutes, date: stamp,
                                 note: note.trimmingCharacters(in: .whitespacesAndNewlines)))
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        let message = "Logged \(TimeFormat.duration(totalMinutes)) · \(activity.name)"
        withAnimation(.spring()) {
            toast = message
            hours = 0
            minutes = 0
            note = ""
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { if toast == message { toast = nil } }
        }
    }
}

// MARK: - Shared pieces

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.leading, 4)
    }
}

struct ActivityChip: View {
    let activity: Activity
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: activity.symbol)
                    .font(.subheadline.weight(.semibold))
                Text(activity.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundColor(isSelected ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? activity.color : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(activity.color.opacity(isSelected ? 0 : 0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ActivityIcon: View {
    let activity: Activity?
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle().fill((activity?.color ?? .gray).opacity(0.18))
            Image(systemName: activity?.symbol ?? "questionmark")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundColor(activity?.color ?? .gray)
        }
        .frame(width: size, height: size)
    }
}

struct EntryRow: View {
    @EnvironmentObject private var store: DataStore
    let entry: TimeEntry
    var showDate = false

    var body: some View {
        let activity = store.activity(with: entry.activityID)
        HStack(spacing: 12) {
            ActivityIcon(activity: activity)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity?.name ?? "Deleted activity")
                    .font(.body)
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if showDate {
                    Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text(TimeFormat.duration(entry.minutes))
                .font(.body.monospacedDigit().weight(.semibold))
        }
    }
}
