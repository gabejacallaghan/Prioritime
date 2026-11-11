import SwiftUI
import Charts

struct ActivityTotal: Identifiable {
    let activity: Activity
    let minutes: Int
    var id: UUID { activity.id }
    var hours: Double { Double(minutes) / 60 }
}

struct DailyPoint: Identifiable {
    let id = UUID()
    let day: Date
    let name: String
    let hours: Double
}

struct StatsView: View {
    @EnvironmentObject private var store: DataStore
    @State private var kind: PeriodKind = .week
    @State private var offset = 0
    @State private var showingAI = false

    private var period: Period { Period(kind: kind, offset: offset) }

    var body: some View {
        let period = self.period
        let entries = store.entries(in: period.interval)
        let totals = InsightsEngine.totalsByActivity(entries)
        let rows = store.activities
            .map { ActivityTotal(activity: $0, minutes: totals[$0.id] ?? 0) }
            .filter { $0.minutes > 0 }
            .sorted { $0.minutes > $1.minutes }
        let total = rows.reduce(0) { $0 + $1.minutes }

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Period", selection: $kind) {
                        ForEach(PeriodKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    periodNavigator(period)
                    summaryCard(total: total, activityCount: rows.count)

                    Button { showingAI = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles").font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Insights").font(.headline)
                                Text("Use AI to find patterns in your time and your days")
                                    .font(.caption)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .padding()
                        .foregroundColor(.white)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.accentColor))
                    }
                    .buttonStyle(.plain)

                    Card(title: "Where your time went") {
                        if rows.isEmpty {
                            emptyChart
                        } else {
                            rankingChart(rows)
                        }
                    }

                    if !rows.isEmpty {
                        Card(title: period.kind == .week ? "Day by day" : "Through the month") {
                            dailyChart(entries: entries, rows: rows, period: period)
                        }
                    }

                    if !store.checkIns.isEmpty || store.checkInSettings.enabled {
                        MoodCard(checkIns: store.checkIns.filter { period.contains($0.day) }, period: period)
                    }

                    Card(title: "Insights") {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(insights(for: period)) { insight in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: insight.symbol)
                                        .font(.body.weight(.semibold))
                                        .foregroundColor(insight.tint)
                                        .frame(width: 24)
                                    Text(insight.text)
                                        .font(.subheadline)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stats")
            .sheet(isPresented: $showingAI) {
                AIInsightsView().environmentObject(store)
            }
            .onChange(of: kind) { _ in offset = 0 }
        }
    }

    private func insights(for period: Period) -> [Insight] {
        InsightsEngine.insights(activities: store.activities, allEntries: store.entries, period: period)
            + MoodInsights.insights(checkIns: store.checkIns, allEntries: store.entries,
                                    activities: store.activities, period: period)
    }

    // MARK: Pieces

    private func periodNavigator(_ period: Period) -> some View {
        HStack {
            Button { withAnimation { offset -= 1 } } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
            }
            Spacer()
            VStack(spacing: 2) {
                Text(period.title).font(.headline)
                if offset == 0 {
                    Text("This \(kind.noun)").font(.caption).foregroundColor(.secondary)
                } else {
                    Button("Back to this \(kind.noun)") { withAnimation { offset = 0 } }
                        .font(.caption)
                }
            }
            Spacer()
            Button { withAnimation { offset += 1 } } label: {
                Image(systemName: "chevron.right").font(.headline).frame(width: 44, height: 44)
            }
            .disabled(offset >= 0)
        }
    }

    private func summaryCard(total: Int, activityCount: Int) -> some View {
        HStack(spacing: 12) {
            StatTile(value: TimeFormat.duration(total), label: "Total logged")
            StatTile(value: "\(activityCount)", label: activityCount == 1 ? "Activity" : "Activities")
        }
    }

    private var emptyChart: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No time logged this \(kind.noun)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    private func rankingChart(_ rows: [ActivityTotal]) -> some View {
        let maxHours = rows.map(\.hours).max() ?? 1
        return Chart(rows) { row in
            BarMark(x: .value("Hours", row.hours),
                    y: .value("Activity", row.activity.name))
                .foregroundStyle(row.activity.color)
                .cornerRadius(6)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(TimeFormat.duration(row.minutes))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
        }
        .chartYScale(domain: rows.map { $0.activity.name })
        .chartXScale(domain: 0...(maxHours * 1.3))
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    Text(Self.hoursLabel(value.as(Double.self) ?? 0))
                }
            }
        }
        .frame(height: CGFloat(rows.count) * 42 + 30)
    }

    private func dailyChart(entries: [TimeEntry], rows: [ActivityTotal], period: Period) -> some View {
        let cal = Calendar.current
        var points: [DailyPoint] = []
        let grouped = Dictionary(grouping: entries) { cal.startOfDay(for: $0.date) }
        for (day, dayEntries) in grouped {
            let byActivity = InsightsEngine.totalsByActivity(dayEntries)
            for row in rows {
                if let m = byActivity[row.activity.id], m > 0 {
                    points.append(DailyPoint(day: day, name: row.activity.name, hours: Double(m) / 60))
                }
            }
        }
        let names = rows.map { $0.activity.name }
        let colors = rows.map { $0.activity.color }

        return Chart(points) { point in
            BarMark(x: .value("Day", point.day, unit: .day),
                    y: .value("Hours", point.hours))
                .foregroundStyle(by: .value("Activity", point.name))
        }
        .chartForegroundStyleScale(domain: names, range: colors)
        .chartXScale(domain: period.interval.start...period.interval.end)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: period.kind == .week ? 1 : 7)) { value in
                AxisGridLine()
                AxisValueLabel {
                    Text(Self.dayLabel(value.as(Date.self), kind: period.kind))
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    Text(Self.hoursLabel(value.as(Double.self) ?? 0))
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 220)
    }

    static func dayLabel(_ date: Date?, kind: PeriodKind) -> String {
        guard let date = date else { return "" }
        return kind == .week
            ? date.formatted(.dateTime.weekday(.abbreviated))
            : date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func hoursLabel(_ hours: Double) -> String {
        if hours == hours.rounded() { return "\(Int(hours))h" }
        return String(format: "%.1fh", hours)
    }
}

// MARK: - Reusable cards

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
