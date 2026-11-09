import SwiftUI

struct ActivitiesView: View {
    @EnvironmentObject private var store: DataStore
    @State private var editing: Activity?
    @State private var showingNew = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.activities) { activity in
                        Button { editing = activity } label: {
                            HStack(spacing: 12) {
                                ActivityIcon(activity: activity, size: 34)
                                Text(activity.name).foregroundColor(.primary)
                                Spacer()
                                let count = store.entryCount(for: activity)
                                Text(count == 1 ? "1 entry" : "\(count) entries")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Color(.tertiaryLabel))
                            }
                        }
                    }
                    .onMove { store.moveActivities(from: $0, to: $1) }
                } footer: {
                    Text("Tap an activity to rename it or change its color and icon. Use Edit to reorder.")
                }
            }
            .navigationTitle("Activities")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { EditButton() }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New activity")
                }
            }
            .sheet(item: $editing) { activity in
                ActivityEditorView(activity: activity).environmentObject(store)
            }
            .sheet(isPresented: $showingNew) {
                ActivityEditorView(activity: nil).environmentObject(store)
            }
        }
    }
}

struct ActivityEditorView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let original: Activity?
    var onCreate: ((Activity) -> Void)?

    @State private var name: String
    @State private var colorIndex: Int
    @State private var symbol: String
    @State private var confirmingDelete = false

    init(activity: Activity?, onCreate: ((Activity) -> Void)? = nil) {
        original = activity
        self.onCreate = onCreate
        _name = State(initialValue: activity?.name ?? "")
        _colorIndex = State(initialValue: activity?.colorIndex ?? Int.random(in: 0..<Palette.colors.count))
        _symbol = State(initialValue: activity?.symbol ?? "star")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var nameTaken: Bool { store.isNameTaken(trimmedName, excluding: original?.id) }
    private var canSave: Bool { !trimmedName.isEmpty && !nameTaken }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ActivityIcon(activity: Activity(name: name, colorIndex: colorIndex, symbol: symbol), size: 72)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    TextField("Name (e.g. Homework)", text: $name)
                        .font(.title3)
                    if nameTaken {
                        Text("You already have an activity with this name.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                        ForEach(Palette.colors.indices, id: \.self) { i in
                            Circle()
                                .fill(Palette.color(i))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle().strokeBorder(Color.primary, lineWidth: i == colorIndex ? 3 : 0)
                                        .padding(-4)
                                )
                                .onTapGesture { colorIndex = i }
                                .accessibilityLabel("Color \(i + 1)")
                                .accessibilityAddTraits(i == colorIndex ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Palette.symbols, id: \.self) { s in
                            Image(systemName: s)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .foregroundColor(s == symbol ? .white : .primary)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(s == symbol ? Palette.color(colorIndex) : Color(.tertiarySystemFill))
                                )
                                .onTapGesture { symbol = s }
                        }
                    }
                    .padding(.vertical, 6)
                }

                if let original = original {
                    Section {
                        Button("Delete Activity", role: .destructive) { confirmingDelete = true }
                    } footer: {
                        let count = store.entryCount(for: original)
                        if count > 0 {
                            Text("Deleting also removes its \(count) logged \(count == 1 ? "entry" : "entries").")
                        }
                    }
                }
            }
            .navigationTitle(original == nil ? "New Activity" : "Edit Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .confirmationDialog("Delete \(original?.name ?? "activity")?",
                                isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Activity and Entries", role: .destructive) {
                    if let original = original { store.deleteActivity(original) }
                    dismiss()
                }
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    private func save() {
        if var updated = original {
            updated.name = trimmedName
            updated.colorIndex = colorIndex
            updated.symbol = symbol
            store.updateActivity(updated)
        } else {
            let created = Activity(name: trimmedName, colorIndex: colorIndex, symbol: symbol)
            store.addActivity(created)
            onCreate?(created)
        }
        dismiss()
    }
}
