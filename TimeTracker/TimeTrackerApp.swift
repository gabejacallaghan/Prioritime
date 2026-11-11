import SwiftUI

@main
struct TimeTrackerApp: App {
    @StateObject private var store = DataStore()
    @ObservedObject private var notifications = NotificationManager.shared

    init() {
        // Touch the manager early so it is the notification delegate before the app finishes launching.
        _ = NotificationManager.shared
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                LogView()
                    .tabItem { Label("Log", systemImage: "plus.circle.fill") }
                StatsView()
                    .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                CheckInView()
                    .tabItem { Label("Check-in", systemImage: "face.smiling") }
                ActivitiesView()
                    .tabItem { Label("Activities", systemImage: "square.grid.2x2.fill") }
            }
            .environmentObject(store)
            .sheet(isPresented: $notifications.showCheckIn) {
                CheckInEditorView(day: Date(), existing: store.checkIn(on: Date()))
                    .environmentObject(store)
            }
            .task {
                // Keep the scheduled reminder in step with the saved settings.
                await NotificationManager.shared.sync(store.checkInSettings)
            }
        }
    }
}
