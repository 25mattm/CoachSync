/// Hosts the primary tab navigation for the iOS app.

import SwiftUI
import SwiftData

/// Root tab container for the main app sections.
struct ContentView: View {
    /// Selection exists so child surfaces can deep-link between tabs
    /// (Dashboard's "+N more" chip jumps to Schedule).
    @State private var selectedTab = 0

    var body: some View {
        // UI tests find tabs by label (`XCUIApplication.tab(_:)`): identifiers set inside
        // `.tabItem` don't reliably reach the tab bar buttons, so none are set here.
        TabView(selection: $selectedTab) {
            DashboardView(onShowSchedule: { selectedTab = 3 })
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            AthletesView()
                .tabItem {
                    Label("Athletes", systemImage: "person.2.fill")
                }
                .tag(1)

            TeamsView()
                .tabItem {
                    Label("Teams", systemImage: "person.3.fill")
                }
                .tag(2)

            ScheduleView()
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
    }
}
