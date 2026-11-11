import SwiftUI

/// "Insights" sheet: sends a summary of the user's data to Claude and shows the patterns it finds.
struct AIInsightsView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage("aiRangeDays") private var rangeDays = 30
    @AppStorage("aiIncludeNotes") private var includeNotes = false
    @AppStorage("aiHasConsented") private var hasConsented = false
    @AppStorage("aiLastInsight") private var lastInsight = ""
    @AppStorage("aiLastInsightDate") private var lastInsightDate = 0.0

    private static let keyAccount = "anthropic-api-key"

    @State private var apiKey: String? = Keychain.read(AIInsightsView.keyAccount)
    @State private var keyField = ""
    @State private var loading = false
    @State private var errorText: String?
    @State private var confirming = false
    @State private var editingKey = false

    private var payload: AIPayload {
        AIPayloadBuilder.build(activities: store.activities, entries: store.entries,
                               checkIns: store.checkIns, days: rangeDays, includeNotes: includeNotes)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro
                    if apiKey == nil || editingKey {
                        keyCard
                    }
                    if apiKey != nil {
                        optionsCard
                        generateSection
                    }
                    if !lastInsight.isEmpty { resultCard }
                    footer
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if apiKey != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { editingKey.toggle() } label: { Image(systemName: "key") }
                            .accessibilityLabel("API key")
                    }
                }
            }
            .confirmationDialog("Send your data to Anthropic?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Send and analyze") {
                    hasConsented = true
                    run()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The summary shown under “What will be sent” goes to Anthropic's API using your key. Nothing is sent until you do this.")
            }
        }
    }

    // MARK: Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Find patterns with AI", systemImage: "sparkles")
                .font(.title3.weight(.semibold))
            Text("Claude looks at where your time went and how your days felt, and points out patterns. It's told to be candid, to show how much data backs each point, and to avoid treating correlation as cause.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(apiKey == nil ? "Add your Anthropic API key" : "Anthropic API key")
                .font(.headline)
            Text("This feature calls the Anthropic API directly from your phone, so it needs your own API key (create one at console.anthropic.com). The key is kept in the iOS Keychain on this device and is only sent to api.anthropic.com. Usage is billed to your Anthropic account.")
                .font(.footnote)
                .foregroundColor(.secondary)
            SecureField("sk-ant-…", text: $keyField)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack {
                Button("Save key") {
                    let trimmed = keyField.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, Keychain.save(trimmed, account: Self.keyAccount) else {
                        errorText = "Couldn't save the key."
                        return
                    }
                    apiKey = trimmed
                    keyField = ""
                    editingKey = false
                    errorText = nil
                }
                .buttonStyle(.borderedProminent)
                .disabled(keyField.trimmingCharacters(in: .whitespaces).isEmpty)

                if apiKey != nil {
                    Spacer()
                    Button("Remove key", role: .destructive) {
                        Keychain.delete(Self.keyAccount)
                        apiKey = nil
                        editingKey = false
                    }
                }
            }
        }
        .cardStyle()
    }

    private var optionsCard: some View {
        let p = payload
        return VStack(alignment: .leading, spacing: 12) {
            Picker("Range", selection: $rangeDays) {
                Text("30 days").tag(30)
                Text("60 days").tag(60)
                Text("90 days").tag(90)
            }
            .pickerStyle(.segmented)

            Toggle(isOn: $includeNotes) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include my written notes")
                    Text("Off by default. Notes can be personal.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            Text("\(p.dayCount) days with data · \(p.entryCount) time entries · \(p.checkInCount) check-ins" +
                 (includeNotes ? " · \(p.noteCount) notes" : ""))
                .font(.footnote)
                .foregroundColor(.secondary)

            DisclosureGroup("What will be sent") {
                Text(p.text)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.top, 6)
            }
            .font(.subheadline)
        }
        .cardStyle()
    }

    @ViewBuilder
    private var generateSection: some View {
        let p = payload
        VStack(spacing: 10) {
            Button {
                if hasConsented { run() } else { confirming = true }
            } label: {
                HStack {
                    if loading { ProgressView().tint(.white) }
                    Text(loading ? "Analyzing…" : (lastInsight.isEmpty ? "Analyze my data" : "Analyze again"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundColor(.white)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(p.hasEnoughData && !loading ? Color.accentColor : Color.gray.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .disabled(!p.hasEnoughData || loading)

            if !p.hasEnoughData {
                Text("Log or check in on at least 5 different days in this range first. With less than that there isn't much to find.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            if let errorText = errorText {
                Text(errorText).font(.footnote).foregroundColor(.red)
            }
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(attributed(lastInsight))
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if lastInsightDate > 0 {
                Text("Generated \(Date(timeIntervalSince1970: lastInsightDate).formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .cardStyle()
    }

    private var footer: some View {
        Text("AI can be wrong. Treat these as questions worth asking, not facts about you. This isn't medical or mental-health advice.")
            .font(.caption)
            .foregroundColor(.secondary)
    }

    // MARK: Actions

    private func run() {
        guard let key = apiKey, !loading else { return }
        let data = payload.text
        loading = true
        errorText = nil
        Task {
            do {
                let text = try await AIInsightsService.generate(data: data, apiKey: key)
                await MainActor.run {
                    lastInsight = text
                    lastInsightDate = Date().timeIntervalSince1970
                    loading = false
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    loading = false
                }
            }
        }
    }

    private func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private extension View {
    func cardStyle() -> some View {
        self.padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
