import SwiftUI

@main
struct TimeTrackerApp: App {
    @StateObject private var store = DataStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                LogView()
                    .tabItem { Label("Log", systemImage: "plus.circle.fill") }
                StatsView()
                    .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                ActivitiesView()
                    .tabItem { Label("Activities", systemImage: "square.grid.2x2.fill") }
            }
            .environmentObject(store)
        }
    }
}
