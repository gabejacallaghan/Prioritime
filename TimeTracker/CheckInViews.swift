import SwiftUI
import Charts

// MARK: - Check-in tab

struct CheckInView: View {
    @EnvironmentObject private var store: DataStore
    @State private var editing: CheckIn?
    @State private var showingToday = false

    private var sorted: [CheckIn] { store.checkIns.sorted { $0.day > $1.day } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    todayCard
                    if !store.checkInSettings.enabled {
                        reminderOffCard
                    }
                    historySection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Check-in")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink { CheckInSettingsView() } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Check-in settings")
                }
            }
            .sheet(isPresented: $showingToday) {
                CheckInEditorView(day: Date(), existing: store.checkIn(on: Date()))
                    .environmentObject(store)
            }
            .sheet(item: $editing) { c in
                CheckInEditorView(day: c.day, existing: c).environmentObject(store)
            }
        }
    }

    private var todayCard: some View {
        let today = store.checkIn(on: Date())
        return VStack(alignment: .leading, spacing: 12) {
            Text(today == nil ? "How was your day?" : "Today's check-in")
                .font(.title3.weight(.semibold))
            if let today = today {
                HStack(spacing: 12) {
                    Text(Mood.emoji(today.rating)).font(.system(size: 40))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Mood.label(today.rating)) · \(today.rating) of 5").font(.headline)
                        if !today.tags.isEmpty {
                            Text(today.tags.map { $0.capitalized }.joined(separator: ", "))
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                }
                Button("Edit") { showingToday = true }
                    .buttonStyle(.bordered)
            } else {
                Text("A quick note to yourself helps you see how your time and your days connect.")
                    .font(.subheadline).foregroundColor(.secondary)
                Button { showingToday = true } label: {
                    Text("Check in now").font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var reminderOffCard: some View {
        NavigationLink { CheckInSettingsView() } label: {
            HStack {
                Image(systemName: "bell")
                Text("Turn on a daily reminder")
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            }
            .font(.subheadline)
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var historySection: some View {
        if !sorted.isEmpty {
            SectionLabel("Past check-ins")
            VStack(spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, c in
                    CheckInRow(checkIn: c)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = c }
                        .contextMenu {
                            Button { editing = c } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) {
                                withAnimation { store.deleteCheckIn(c) }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    if index < sorted.count - 1 { Divider().padding(.leading, 64) }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

struct CheckInRow: View {
    let checkIn: CheckIn

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(Mood.emoji(checkIn.rating)).font(.system(size: 30)).frame(width: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(checkIn.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.body.weight(.medium))
                    Spacer()
                    Text("\(checkIn.rating)/5").font(.subheadline.monospacedDigit()).foregroundColor(.secondary)
                }
                if !checkIn.tags.isEmpty {
                    Text(checkIn.tags.map { $0.capitalized }.joined(separator: " · "))
                        .font(.caption).foregroundColor(.secondary)
                }
                if !checkIn.note.isEmpty {
                    Text(checkIn.note).font(.subheadline).lineLimit(2)
                }
            }
        }
    }
}

// MARK: - Editor

struct CheckInEditorView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let day: Date
    @State private var rating: Int
    @State private var tags: Set<String>
    @State private var note: String
    @State private var newTag = ""

    init(day: Date, existing: CheckIn?) {
        self.day = Calendar.current.startOfDay(for: day)
        _rating = State(initialValue: existing?.rating ?? 0)
        _tags = State(initialValue: Set(existing?.tags ?? []))
        _note = State(initialValue: existing?.note ?? "")
    }

    private var settings: CheckInSettings { store.checkInSettings }

    /// Presets, the user's own tags, and any tag on this check-in that's since been removed.
    private var allTags: [String] {
        var list = Mood.presetTags + settings.customTags
        for t in tags.sorted() where !list.contains(t) { list.append(t) }
        return list
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.subheadline).foregroundColor(.secondary)

                    ratingSection
                    if settings.askForTags { tagSection }
                    if settings.askForNote { noteSection }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("How was your day?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.saveCheckIn(day: day, rating: rating, tags: tags.sorted(),
                                          note: note.trimmingCharacters(in: .whitespacesAndNewlines))
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }
                    .disabled(rating == 0)
                }
            }
        }
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        withAnimation(.easeOut(duration: 0.12)) { rating = value }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        VStack(spacing: 4) {
                            Text(Mood.emoji(value)).font(.system(size: 30))
                            Text("\(value)").font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .foregroundColor(rating == value ? .white : .primary)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(rating == value ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(value) of 5, \(Mood.label(value))")
                    .accessibilityAddTraits(rating == value ? .isSelected : [])
                }
            }
            Text(rating == 0 ? "Pick a number from 1 (rough) to 5 (great)" : Mood.label(rating))
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("How did you feel?")
            FlowLayout(spacing: 8) {
                ForEach(allTags, id: \.self) { tag in
                    let on = tags.contains(tag)
                    Button {
                        if on { tags.remove(tag) } else { tags.insert(tag) }
                    } label: {
                        Text(tag.capitalized)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .foregroundColor(on ? .white : .primary)
                            .background(Capsule().fill(on ? Color.accentColor : Color(.secondarySystemGroupedBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            HStack {
                TextField("Add your own", text: $newTag)
                    .submitLabel(.done)
                    .onSubmit(addTag)
                Button("Add", action: addTag)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Anything to add?")
            TextField("Describe your day (optional)", text: $note, axis: .vertical)
                .lineLimit(4...10)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func addTag() {
        if let tag = store.addCustomTag(newTag) { tags.insert(tag) }
        newTag = ""
    }
}

// MARK: - Settings

struct CheckInSettingsView: View {
    @EnvironmentObject private var store: DataStore
    @ObservedObject private var notifications = NotificationManager.shared
    @State private var showDenied = false

    private var settings: CheckInSettings { store.checkInSettings }

    private func update(_ change: (inout CheckInSettings) -> Void) {
        var s = store.checkInSettings
        change(&s)
        store.updateCheckInSettings(s)
        Task { await NotificationManager.shared.sync(s) }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.enabled },
            set: { on in
                if !on { update { $0.enabled = false }; return }
                Task {
                    let ok = await NotificationManager.shared.requestAuthorization()
                    await MainActor.run {
                        if ok { update { $0.enabled = true } } else { showDenied = true }
                    }
                }
            })
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: settings.hour, minute: settings.minute,
                                         second: 0, of: Date()) ?? Date() },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                update { $0.hour = c.hour ?? 21; $0.minute = c.minute ?? 0 }
            })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Daily reminder", isOn: enabledBinding)
                if settings.enabled {
                    DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                }
            } footer: {
                if notifications.isDenied {
                    Text("Notifications are turned off for Time Tracker. Turn them on in Settings to get reminders.")
                } else {
                    Text("You'll get a notification at this time every day asking how your day was.")
                }
            }

            if notifications.isDenied {
                Section {
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }

            Section {
                Toggle("Feeling tags", isOn: Binding(get: { settings.askForTags },
                                                     set: { v in update { $0.askForTags = v } }))
                Toggle("Written note", isOn: Binding(get: { settings.askForNote },
                                                     set: { v in update { $0.askForNote = v } }))
            } header: {
                Text("What to ask")
            } footer: {
                Text("The 1–5 rating is always included. Turn these off for a faster check-in.")
            }

            if !settings.customTags.isEmpty {
                Section("Your tags") {
                    ForEach(settings.customTags, id: \.self) { Text($0.capitalized) }
                        .onDelete { offsets in
                            update { s in s.customTags.remove(atOffsets: offsets) }
                        }
                }
            }
        }
        .navigationTitle("Check-in Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await notifications.refreshStatus() }
        .alert("Notifications are off", isPresented: $showDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Allow notifications for Time Tracker in iOS Settings to receive the daily reminder.")
        }
    }
}

// MARK: - Home-screen prompt

/// Shown at the top of the Log screen once the reminder time has passed and today hasn't been checked in.
struct CheckInPrompt: View {
    @EnvironmentObject private var store: DataStore
    let action: () -> Void

    static func isDue(settings: CheckInSettings, hasCheckIn: Bool, now: Date = Date()) -> Bool {
        guard settings.enabled, !hasCheckIn else { return false }
        let cal = Calendar.current
        guard let reminder = cal.date(bySettingHour: settings.hour, minute: settings.minute,
                                      second: 0, of: now) else { return false }
        return now >= reminder
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "face.smiling").font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("How was your day?").font(.subheadline.weight(.semibold))
                    Text("Tap to check in").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            }
            .padding()
            .foregroundColor(.primary)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stats card

struct MoodCard: View {
    let checkIns: [CheckIn]
    let period: Period

    private var tagCounts: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for c in checkIns { for t in c.tags { counts[t, default: 0] += 1 } }
        return counts.map { (tag: $0.key, count: $0.value) }
            .sorted { ($0.count, $1.tag) > ($1.count, $0.tag) }
    }

    var body: some View {
        Card(title: "How your days felt") {
            if checkIns.isEmpty {
                Text("No check-ins this \(period.kind.noun).")
                    .font(.subheadline).foregroundColor(.secondary)
            } else {
                let avg = Mood.average(checkIns.map(\.rating))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Mood.format(avg))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    Text("average out of 5 · \(checkIns.count) \(checkIns.count == 1 ? "check-in" : "check-ins")")
                        .font(.subheadline).foregroundColor(.secondary)
                }

                Chart(checkIns) { c in
                    LineMark(x: .value("Day", c.day, unit: .day), y: .value("Rating", c.rating))
                        .foregroundStyle(Color.accentColor.opacity(0.4))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Day", c.day, unit: .day), y: .value("Rating", c.rating))
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(60)
                }
                .chartYScale(domain: 1...5)
                .chartXScale(domain: period.interval.start...period.interval.end)
                .chartYAxis {
                    AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                        AxisGridLine()
                        AxisValueLabel { Text(Mood.emoji(value.as(Int.self) ?? 0)) }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: period.kind == .week ? 1 : 7)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            Text(StatsView.dayLabel(value.as(Date.self), kind: period.kind))
                        }
                    }
                }
                .frame(height: 160)

                if !tagCounts.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(tagCounts.prefix(8), id: \.tag) { item in
                            Text("\(item.tag.capitalized) ×\(item.count)")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(Color(.tertiarySystemFill)))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Wrapping layout (iOS 16+)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
