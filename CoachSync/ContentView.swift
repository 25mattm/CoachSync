/// Hosts the primary tab navigation for the iOS app.

import SwiftUI
import SwiftData

/// Root tab container for the main app sections.
struct ContentView: View {
    /// Selection exists so child surfaces can deep-link between tabs
    /// (Dashboard's "+N more" chip jumps to Schedule).
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(onShowSchedule: { selectedTab = 3 })
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                        .accessibilityIdentifier("tab.home")
                }
                .tag(0)

            AthletesView()
                .tabItem {
                    Label("Athletes", systemImage: "person.2.fill")
                        .accessibilityIdentifier("tab.athletes")
                }
                .tag(1)

            TeamsView()
                .tabItem {
                    Label("Teams", systemImage: "person.3.fill")
                        .accessibilityIdentifier("tab.teams")
                }
                .tag(2)

            ScheduleView()
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                        .accessibilityIdentifier("tab.schedule")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                        .accessibilityIdentifier("tab.settings")
                }
                .tag(4)
        }
    }
}
