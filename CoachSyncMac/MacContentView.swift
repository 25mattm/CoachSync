/// Hosts the macOS sidebar navigation and routes to the shared feature views.

import SwiftUI
import SwiftData

/// Root navigation container for the macOS app.
struct MacContentView: View {
    @State private var selectedSidebar: SidebarItem = .dashboard
    /// @AppStorage (not a one-shot UserDefaults read) so a club rename in
    /// Settings updates the sidebar footer without relaunching the app.
    @AppStorage("clubName") private var clubName = ""

    /// Sidebar destinations shown in the macOS split view.
    enum SidebarItem: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case athletes  = "Athletes"
        case teams     = "Teams"
        case schedule  = "Schedule"
        case settings  = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .dashboard: return "house.fill"
            case .athletes:  return "person.2.fill"
            case .teams:     return "person.3.fill"
            case .schedule:  return "calendar"
            case .settings:  return "gearshape.fill"
            }
        }

        var color: Color {
            switch self {
            case .dashboard: return .blue
            case .athletes:  return .green
            case .teams:     return .orange
            case .schedule:  return .purple
            case .settings:  return .gray
            }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SidebarItem.allCases, selection: $selectedSidebar) { item in
                Label {
                    Text(item.rawValue)
                        .fontWeight(.medium)
                } icon: {
                    Image(systemName: item.icon)
                        .foregroundStyle(selectedSidebar == item ? Color.accentColor : Color.secondary)
                }
                .tag(item)
                .padding(.vertical, 4)
            }
            .navigationTitle("CoachSync")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
            .listStyle(.sidebar)

            // Sidebar footer
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                Text(clubName.isEmpty ? "CoachSync" : clubName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        } detail: {
            switch selectedSidebar {
            case .dashboard: DashboardView(onShowSchedule: { selectedSidebar = .schedule })
            case .athletes:  AthletesView()
            case .teams:     TeamsView()
            case .schedule:  ScheduleView()
            case .settings:  SettingsView()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
