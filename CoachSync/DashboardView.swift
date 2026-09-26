/// Shows today's sessions, upcoming work, and recent completions.

import SwiftUI
import SwiftData

/// Home view for day-to-day coaching activity.
struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    /// All non-archived sessions. Date scoping happens in the computed
    /// buckets below at render time — a year window captured here in `init`
    /// would go stale when the app stays resident across Jan 1 and would
    /// hide sessions scheduled into the next year.
    @Query(filter: #Predicate<CoachSession> { !$0.isArchived },
           sort: \CoachSession.scheduledDate)
    private var activeSessions: [CoachSession]
    @State private var showingAddSession = false
    @State private var sessionToLog: CoachSession? = nil
    @State private var didAppear = false
#if os(iOS)
    @State private var weather = WeatherManager()
    @Environment(\.scenePhase) private var scenePhase
#endif

    /// Host-provided navigation to the Schedule surface — the iOS TabView and
    /// the Mac sidebar switch differently, so the chip calls back instead of
    /// the shared view knowing about either.
    var onShowSchedule: (() -> Void)? = nil

    /// Open sessions scheduled for today — the primary "log now" bucket.
    private var todaysSessions: [CoachSession] {
        activeSessions.filter {
            Calendar.current.isDateInToday($0.scheduledDate) && $0.status.isOpen
        }
    }

    /// Open sessions dated after today — shown in the horizontal Upcoming scroller.
    private var futureSessions: [CoachSession] {
        activeSessions.filter {
            $0.scheduledDate > Calendar.current.startOfDay(for: Date()) &&
            !Calendar.current.isDateInToday($0.scheduledDate) &&
            $0.status.isOpen
        }
    }

    /// Completed sessions, newest first — the Recent bucket.
    private var completedSessions: [CoachSession] {
        activeSessions
            .filter { $0.status == .completed }
            .sorted { $0.scheduledDate > $1.scheduledDate }
    }

    /// Past-dated sessions still open — practices the coach never marked
    /// completed or cancelled. Without this bucket they fall between Today
    /// and Recent and silently vanish from the dashboard.
    private var unloggedSessions: [CoachSession] {
        activeSessions
            .filter {
                $0.status.isOpen &&
                $0.scheduledDate < Calendar.current.startOfDay(for: Date())
            }
            .sorted { $0.scheduledDate > $1.scheduledDate }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

#if os(iOS)
                    WeatherCardView(weather: weather)
                        .task { await weather.refreshIfStale() }
#endif

                    NeedsAttentionSection()

                    SectionHeader(title: "Today's Practices")

                    if todaysSessions.isEmpty {
                        // Tap target, not just an empty state — matches the
                        // "Add Practice on This Day" pattern on Schedule.
                        Button { showingAddSession = true } label: {
                            EmptyCard(message: "No practices scheduled for today — tap to add one",
                                      systemImage: "calendar.badge.plus")
                        }
                        .buttonStyle(.plain)
                    } else {
                        ForEach(todaysSessions) { session in
                            Button { sessionToLog = session } label: {
                                SessionCard(session: session)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("dashboard.todaySessionCard")
                        }
                    }

                    if !unloggedSessions.isEmpty {
                        SectionHeader(title: "Needs Logging")
                        ForEach(unloggedSessions.prefix(3)) { session in
                            Button { sessionToLog = session } label: {
                                RecentCard(session: session)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            .buttonStyle(.plain)
                        }
                        if unloggedSessions.count > 3 {
                            Text("+ \(unloggedSessions.count - 3) more on the Schedule")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !futureSessions.isEmpty {
                        SectionHeader(title: "Upcoming")
                        ScrollView(.horizontal, showsIndicators: false) {
                            if #available(iOS 26, *) {
                                GlassEffectContainer(spacing: 12) {
                                    HStack(spacing: 12) {
                                        ForEach(futureSessions.prefix(10)) { session in
                                            Button { sessionToLog = session } label: {
                                                UpcomingChip(session: session)
                                                    .transition(.asymmetric(
                                                        insertion: .move(edge: .trailing).combined(with: .opacity),
                                                        removal: .move(edge: .leading).combined(with: .opacity)
                                                    ))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        if futureSessions.count > 10, let onShowSchedule {
                                            MoreSessionsChip(count: futureSessions.count - 10,
                                                             action: onShowSchedule)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            } else {
                                HStack(spacing: 12) {
                                    ForEach(futureSessions.prefix(10)) { session in
                                        Button { sessionToLog = session } label: {
                                            UpcomingChip(session: session)
                                                .transition(.asymmetric(
                                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .move(edge: .leading).combined(with: .opacity)
                                                ))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    if futureSessions.count > 10, let onShowSchedule {
                                        MoreSessionsChip(count: futureSessions.count - 10,
                                                         action: onShowSchedule)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.horizontal, -16)
                    }

                    if !completedSessions.isEmpty {
                        SectionHeader(title: "Recent")
                        ForEach(completedSessions.prefix(3)) { session in
                            Button { sessionToLog = session } label: {
                                RecentCard(session: session)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .animation(didAppear ? .snappy(duration: 0.2) : nil, value: activeSessions)
                .padding(16)
            }
            .navigationTitle(
                Date.now.formatted(.dateTime.weekday(.wide).month().day())
            )
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button { showingAddSession = true } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                    .accessibilityLabel("Add practice")
                    .accessibilityIdentifier("dashboard.addPracticeButton")
                }
            }
            .sheet(isPresented: $showingAddSession) {
                AddSessionSheet()
#if os(macOS)
                .frame(minWidth: 520, minHeight: 560)
#endif
            }
#if os(iOS)
            .fullScreenCover(item: $sessionToLog) { session in
                SessionLoggerView(session: session)
            }
#else
            .sheet(item: $sessionToLog) { session in
                SessionLoggerView(session: session)
            }
#endif
            .onAppear { didAppear = true }
#if os(iOS)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await weather.refreshIfStale() }
                }
            }
#endif
        }
    }
}

// MARK: - Session Card

/// Prominent card used for sessions that can be logged from the dashboard.
struct SessionCard: View {
    let session: CoachSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// A practice with no team is logged for every active athlete (the logger's own fallback), so
    /// the card counts them too — counting only team members showed "0 athletes" here.
    @Query(filter: #Predicate<Athlete> { $0.isActive }) private var activeAthletes: [Athlete]

    private var athleteCount: Int { session.team?.activeMembers.count ?? activeAthletes.count }

    /// Side by side normally; stacked at accessibility text sizes, where one row can't fit the
    /// time, the athlete count, and "Log Practice" without breaking words apart.
    private var detailsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 16))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.sessionName)
                        .font(.headline)
                    if let team = session.team {
                        Text(team.teamName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let cue = session.mfCue {
                        Text(cue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }
                Spacer()
                StatusPill(status: session.status)
                    .animation(.smooth, value: session.status)
            }
            detailsLayout {
                if let start = session.startTime {
                    Label(
                        start.formatted(.dateTime.hour().minute()),
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "person.2")
                    Text("\(athleteCount)")
                        .contentTransition(.numericText(value: Double(athleteCount)))
                    Text(athleteCount == 1 ? "athlete" : "athletes")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .animation(.snappy, value: athleteCount)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer()
                }
                HStack(spacing: 3) {
                    Text("Log Practice")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
                .foregroundStyle(.blue.opacity(0.8))
            }
        }
        .padding(16)
        .background(
            Group {
                if #available(iOS 26, *) { Color.clear }
                else { RoundedRectangle(cornerRadius: 14).fill(.regularMaterial) }
            }
        )
        .ifAvailableiOS26 { $0.glassEffect(.regular.tint(session.status.color.opacity(0.15)), in: .rect(cornerRadius: 14)) }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(session.status.color.opacity(0.3), lineWidth: 1.5)
        )
    }
}

// MARK: - Upcoming Chip

/// Compact summary for an upcoming session in the horizontal scroller.
struct UpcomingChip: View {
    let session: CoachSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.scheduledDate.formatted(.dateTime.month(.abbreviated).day()))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(session.sessionName)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
            if let team = session.team {
                Text(team.teamName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 130, alignment: .leading)
        .padding(12)
        .background(
            Group {
                if #available(iOS 26, *) { Color.clear }
                else { RoundedRectangle(cornerRadius: 12).fill(.regularMaterial) }
            }
        )
        .ifAvailableiOS26 { $0.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12)) }
    }
}

// MARK: - More Sessions Chip

/// Trailing chip in the Upcoming scroller when more sessions exist than the
/// row shows — taps through to the full Schedule.
private struct MoreSessionsChip: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text("+\(count) more")
                    .font(.caption)
                    .fontWeight(.semibold)
                Image(systemName: "arrow.right")
                    .font(.caption2)
            }
            .foregroundStyle(Color.accentColor)
            .frame(width: 80)
            .frame(maxHeight: .infinity)
            .padding(12)
            .background(
                Group {
                    if #available(iOS 26, *) { Color.clear }
                    else { RoundedRectangle(cornerRadius: 12).fill(.regularMaterial) }
                }
            )
            .ifAvailableiOS26 { $0.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12)) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) more upcoming practices — show Schedule")
    }
}

// MARK: - Recent Card

/// Summary card for a recently completed session.
struct RecentCard: View {
    let session: CoachSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.sessionName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let team = session.team {
                    Text(team.teamName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(session.scheduledDate.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    StatusPill(status: session.status)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            Group {
                if #available(iOS 26, *) { Color.clear }
                else { RoundedRectangle(cornerRadius: 12).fill(.regularMaterial) }
            }
        )
        .ifAvailableiOS26 { $0.glassEffect(.regular, in: .rect(cornerRadius: 12)) }
    }
}

// MARK: - Needs Attention Section

/// Shows athletes with active negative insight signals so the coach can act before a session.
struct NeedsAttentionSection: View {
    @Query(filter: #Predicate<Athlete> { $0.isActive }, sort: \Athlete.lastName)
    private var athletes: [Athlete]

    struct AthleteAlert: Identifiable {
        let athlete: Athlete
        let firstSignal: String
        var id: UUID { athlete.id }
    }

    private var alertedAthletes: [AthleteAlert] {
        Self.alertsSortedForDisplay(from: athletes)
    }

    /// Builds and orders the needs-attention list: flagged athletes, sorted by last name then
    /// first name (case-insensitively) so the surfaced rows — and the boundary athlete at the
    /// five-row cap applied by the caller — match the backend's `NeedsAttentionService` ordering.
    /// `internal` (not `private`) and free of any SwiftUI/`@Query` dependency so it's unit-testable
    /// directly with a hand-built athlete array.
    static func alertsSortedForDisplay(from athletes: [Athlete]) -> [AthleteAlert] {
        athletes.compactMap { athlete in
            // Signal math lives in InsightSignals.swift.
            if let block = athlete.decliningBlockName {
                return AthleteAlert(athlete: athlete, firstSignal: "\(block): declining")
            }
            if let pacing = athlete.inconsistentPacingBlock?.name {
                return AthleteAlert(athlete: athlete, firstSignal: "\(pacing): erratic pacing")
            }
            return nil
        }
        .sorted { lhs, rhs in
            switch lhs.athlete.lastName.localizedCaseInsensitiveCompare(rhs.athlete.lastName) {
            case .orderedSame:
                return lhs.athlete.firstName.localizedCaseInsensitiveCompare(rhs.athlete.firstName) == .orderedAscending
            case .orderedAscending:
                return true
            case .orderedDescending:
                return false
            }
        }
    }

    var body: some View {
        if !alertedAthletes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    SectionHeader(title: "Needs Attention")
                    // Full signal count — the list below caps at five rows.
                    Text("\(alertedAthletes.count)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                    Spacer()
                }
                alertRows
            }
            .padding(12)
            .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1.5)
            )
        }
    }

    private var alertRows: some View {
            VStack(spacing: 8) {
                ForEach(alertedAthletes.prefix(5)) { alert in
                    NavigationLink(destination: AthleteProfileView(athlete: alert.athlete)) {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alert.athlete.fullName)
                                    .font(.subheadline).fontWeight(.medium)
                                Text(alert.firstSignal)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(
                            Group {
                                if #available(iOS 26, *) { Color.clear }
                                else { RoundedRectangle(cornerRadius: 12).fill(.regularMaterial) }
                            }
                        )
                        .ifAvailableiOS26 { $0.glassEffect(.regular, in: .rect(cornerRadius: 12)) }
                    }
                    .buttonStyle(.plain)
                }
            }
    }

}

