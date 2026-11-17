/// Presents an athlete's profile, training history, and supporting summary sections.

import SwiftUI
import SwiftData
import Charts

/// Tab sections within the athlete profile.
enum ProfileTab: String, CaseIterable {
    case overview    = "Overview"
    case performance = "Performance"
    case development = "Development"
    case notes       = "Notes"
}

/// Anchor targets for the Development tab's jump-nav chip strip.
/// (The journal anchor left with the journal itself — it now lives on the
/// Notes tab behind the merged-notes filter, sketch H.)
private enum DevAnchor: String, CaseIterable {
    case technical = "Technical"
    case focus     = "Focus"
    case fitness   = "Fitness"
    case height    = "Height"
    case ktc       = "KTC"
}

/// Filter for the merged Notes tab (sketch H): session-scoped coach notes and
/// the development journal in one place, instead of two notes systems split
/// across tabs.
private enum NotesFilter: String, CaseIterable {
    case all      = "All"
    case practice = "Practice"
    case journal  = "Journal"
}

/// Composite profile screen for a single athlete.
///
/// The view is intentionally sectioned into smaller subviews so each data source can evolve
/// independently without making the profile body unreadable.
struct AthleteProfileView: View {
    @Bindable var athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingEditAthlete = false
    @State private var selectedTab: ProfileTab = .overview
    @State private var notesFilter: NotesFilter = .all

    /// Segments can't grow with Dynamic Type, so a menu takes over at accessibility sizes.
    @ViewBuilder private var sectionPicker: some View {
        let picker = Picker("Section", selection: $selectedTab) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ProfileHeaderView(athlete: athlete)

                    sectionPicker

                    if selectedTab == .development {
                        devAnchorStrip(proxy: proxy)
                    }

                    profileContent
                }
                .padding(16)
            }
        }
        .navigationTitle(athlete.fullName)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Edit") {
                    showingEditAthlete = true
                }
            }
        }
        .sheet(isPresented: $showingEditAthlete) {
            EditAthleteSheet(athlete: athlete)
#if os(macOS)
                .frame(minWidth: 520, minHeight: 640)
#endif
        }
    }

    /// Jump-nav chips for the long Development tab — a pure navigation aid,
    /// hidden on the other tabs (addresses FlowPolish sketch E / F3).
    /// Uses the wrapping FlowLayout rather than a horizontal ScrollView:
    /// a nested scroll view under the same ScrollViewReader makes
    /// `proxy.scrollTo` a no-op (verified on iOS 26 sim) and fights the
    /// chip taps for the drag gesture.
    private func devAnchorStrip(proxy: ScrollViewProxy) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(DevAnchor.allCases, id: \.self) { anchor in
                Button {
                    withAnimation(Motion.animation(.easeInOut(duration: 0.25))) {
                        proxy.scrollTo(anchor, anchor: .top)
                    }
                } label: {
                    Text(anchor.rawValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var profileContent: some View {
        switch selectedTab {
        case .overview:
            VStack(alignment: .leading, spacing: 24) {
                AthleteInsightSection(athlete: athlete)
                Divider()
                TeamMembershipsSection(athlete: athlete)
                Divider()
                SessionHistorySection(athlete: athlete)
            }
        case .performance:
            VStack(alignment: .leading, spacing: 24) {
                PerformanceLogSection(athlete: athlete)
                Divider()
                RegattaResultsSection(athlete: athlete)
                Divider()
                LoadSection(athlete: athlete)
            }
        case .development:
            VStack(alignment: .leading, spacing: 24) {
                TechnicalSummarySection(athlete: athlete).id(DevAnchor.technical)
                Divider()
                DevelopmentFocusPanel(athlete: athlete).id(DevAnchor.focus)
                Divider()
                FitnessTestsSummarySection(athlete: athlete).id(DevAnchor.fitness)
                Divider()
                HeightGrowthSection(athlete: athlete).id(DevAnchor.height)
                Divider()
                KTCScoresSection(athlete: athlete).id(DevAnchor.ktc)
            }
        case .notes:
            // Sketch H: both notes systems live here behind one filter —
            // session-scoped coach notes (read-only on the profile; written
            // from the logger) and the development journal (add/delete here).
            VStack(alignment: .leading, spacing: 20) {
                Picker("Notes filter", selection: $notesFilter) {
                    ForEach(NotesFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                if notesFilter != .journal {
                    NotesSection(athlete: athlete)
                }
                if notesFilter == .all {
                    Divider()
                }
                if notesFilter != .practice {
                    DevelopmentJournalSection(athlete: athlete)
                }
            }
        }
    }
}

// MARK: - Profile Header

/// Header summary with identity and current participation status.
struct ProfileHeaderView: View {
    let athlete: Athlete

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.ageCategory(athlete.ageCategory).opacity(0.15))
                .frame(width: 72, height: 72)
                .overlay(
                    Text(athlete.firstName.prefix(1) + athlete.lastName.prefix(1))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.ageCategory(athlete.ageCategory))
                        .accessibilityHidden(true)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(athlete.fullName)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 8) {
                    CategoryPill(category: athlete.ageCategory)

                    Text(formattedDOB)
                        .font(.caption)
                        .foregroundStyle(Color.readableSecondary)
                }

                if !athlete.isActive {
                    Text("Inactive")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.filledRed)
                        .clipShape(Capsule())
                }
            }
            Spacer()
        }
    }

    /// Formats the date of birth for display in the profile header.
    var formattedDOB: String {
        athlete.dateOfBirth.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

// MARK: - Team Memberships

/// Shows the athlete's current team memberships.
struct TeamMembershipsSection: View {
    let athlete: Athlete

    var activeTeams: [TeamMembership] {
        (athlete.memberships ?? []).filter { $0.leftDate == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Teams")

            if activeTeams.isEmpty {
                Text("Not currently on any teams")
                    .font(.subheadline)
                    .foregroundStyle(Color.readableSecondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(activeTeams) { membership in
                        if let team = membership.team {
                            Text(team.teamName)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.1))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Session History

/// Summarizes recent attendance for the athlete.
struct SessionHistorySection: View {
    let athlete: Athlete

    var attendanceRecords: [AttendanceRecord] {
        (athlete.attendanceRecords ?? [])
            .sorted { lhs, rhs in
                let lhsDate = lhs.session?.scheduledDate ?? .distantPast
                let rhsDate = rhs.session?.scheduledDate ?? .distantPast
                return lhsDate > rhsDate
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdaptiveStack {
                SectionHeader(title: "Practice History")
                AdaptiveSpacer()
                Text("\(attendanceRecords.count) practice\(attendanceRecords.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Color.readableSecondary)
            }

            if attendanceRecords.isEmpty {
                Text("No practices recorded yet")
                    .font(.subheadline)
                    .foregroundStyle(Color.readableSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(attendanceRecords.prefix(5)) { record in
                        AttendanceRow(record: record)
                    }
                    if attendanceRecords.count > 5 {
                        Text("+ \(attendanceRecords.count - 5) more practice\(attendanceRecords.count - 5 == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(Color.readableSecondary)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }
}

/// Single attendance row within the recent session history summary.
struct AttendanceRow: View {
    let record: AttendanceRecord

    var body: some View {
        AdaptiveStack {
            Circle()
                .fill(statusColor.opacity(0.15))
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(statusColor, lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(record.session?.sessionName ?? "Unknown Practice")
                    .font(.subheadline)
                if let date = record.session?.scheduledDate {
                    Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(.caption)
                        .foregroundStyle(Color.readableSecondary)
                }
            }

            AdaptiveSpacer()

            Text(record.status.rawValue)
                .font(.caption)
                .foregroundStyle(statusColor)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    var statusColor: Color {
        switch record.status {
        case .present: return .readableGreen
        case .absent:  return .readableRed
        case .excused: return .readableOrange
        }
    }
}

// MARK: - Performance Log

/// Groups recent performance records by block name for quick comparison.
struct PerformanceLogSection: View {
    let athlete: Athlete

    /// Groups timed performance records by block name after removing DNS, DNF, and empty entries.
    var groupedRecords: [(blockName: String, records: [PerformanceRecord])] {
        let allRecords = (athlete.performanceRecords ?? [])
            .filter { $0.status == .complete && $0.recordedTimeMs != nil }
            .sorted { lhs, rhs in
                let lhsDate = lhs.sessionBlock?.session?.scheduledDate ?? .distantPast
                let rhsDate = rhs.sessionBlock?.session?.scheduledDate ?? .distantPast
                return lhsDate > rhsDate
            }

        let grouped = Dictionary(grouping: allRecords) {
            $0.sessionBlock?.blockName ?? "Unknown"
        }

        return grouped.map { (blockName: $0.key, records: $0.value) }
            .sorted { $0.blockName < $1.blockName }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Performance")

            if groupedRecords.isEmpty {
                Text("No performance data recorded yet")
                    .font(.subheadline)
                    .foregroundStyle(Color.readableSecondary)
            } else {
                ForEach(groupedRecords, id: \.blockName) { group in
                    PerformanceBlockCard(blockName: group.blockName,
                                        records: group.records,
                                        athlete: athlete)
                }
            }
        }
    }
}

/// Card showing the athlete's best and most recent results for one block type.
struct PerformanceBlockCard: View {
    let blockName: String
    let records: [PerformanceRecord]
    let athlete: Athlete

    var personalBest: PerformanceRecord? {
        records.compactMap { $0.recordedTimeMs != nil ? $0 : nil }
               .min { ($0.recordedTimeMs ?? Int.max) < ($1.recordedTimeMs ?? Int.max) }
    }

    var standardDistance: Int? {
        let distances = Set(records.compactMap { record in
            if let metres = record.sessionBlock?.targetDistanceMetres {
                return Int(metres.rounded())
            }
            if let km = record.sessionBlock?.distanceKm {
                return Int((km * 1000).rounded())
            }
            return nil
        }.filter { [200, 500, 1000].contains($0) })

        if distances.count == 1 {
            return distances.first
        }
        return nil
    }

    var regattaResultsForDistance: [RegattaResult] {
        guard let standardDistance else { return [] }
        return (athlete.regattaResults ?? [])
            .filter { $0.eventDistance == standardDistance }
            .sorted { $0.regattaDate < $1.regattaDate }
    }

    /// Last 3 unique sessions for this block — best rep time per session and any athlete note.
    var recentSessions: [(date: Date, bestTime: String, note: String?)] {
        let bySession = Dictionary(grouping: records) { record -> UUID in
            record.sessionBlock?.session?.id ?? UUID()
        }
        let entries: [(date: Date, bestTime: String, note: String?)] = bySession.compactMap { _, sessionRecords in
            guard let session = sessionRecords.first?.sessionBlock?.session else { return nil }
            guard let bestMs = sessionRecords.compactMap(\.recordedTimeMs).min(),
                  let best = sessionRecords.first(where: { $0.recordedTimeMs == bestMs })
            else { return nil }
            let noteText = (athlete.notes ?? []).first { $0.session?.id == session.id }?.noteText
            return (date: session.scheduledDate, bestTime: best.formattedTime ?? "—", note: noteText)
        }
        return entries.sorted { $0.date > $1.date }.prefix(3).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(blockName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if let pb = personalBest?.formattedTime {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.readableYellow)
                        Text("PB \(pb)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.readableSecondary)
                    }
                }
            }

            // Trend chart placeholder — full chart comes next session
            TrendChartView(records: records, regattaResults: regattaResultsForDistance)

            // Last 3 sessions — best rep time and inline athlete note
            VStack(spacing: 6) {
                ForEach(recentSessions, id: \.date) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(entry.date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption)
                                .foregroundStyle(Color.readableSecondary)
                            Spacer()
                            Text(entry.bestTime)
                                .font(.caption)
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                        if let note = entry.note {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "bubble.left")
                                    .font(.caption2)
                                    .foregroundStyle(Color.readableSecondary)
                                Text(note)
                                    .font(.caption2)
                                    .foregroundStyle(Color.readableSecondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Trend Chart

/// Combines practice and regatta results into a small trend chart.
///
/// The chart keeps only the most recent points so the profile stays legible on smaller screens.
struct TrendChartView: View {
    let records: [PerformanceRecord]
    let regattaResults: [RegattaResult]

    /// Chart annotation size — 9pt at default text size (deliberately small;
    /// these are axis/PB labels inside a 120pt chart), but scaled so the last
    /// two fixed-size fonts in the app track Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var chartLabelSize: CGFloat = 9

    /// Normalized chart points ordered from oldest to newest so trend direction is meaningful.
    var chartData: [TrendDataPoint] {
        let practicePoints = records.compactMap { record -> TrendDataPoint? in
            guard let ms = record.recordedTimeMs else { return nil }
            let date = record.sessionBlock?.session?.scheduledDate ?? .distantPast
            return TrendDataPoint(date: date, timeMs: ms, source: .practice)
        }

        let regattaPoints = regattaResults.map {
            TrendDataPoint(date: $0.regattaDate, timeMs: $0.resultTimeMs, source: .regatta)
        }

        return (practicePoints + regattaPoints)
            .sorted { $0.date < $1.date }
            .suffix(10)
            .map { $0 }
    }

    var personalBestMs: Int? {
        chartData.map { $0.timeMs }.min()
    }

    /// Uses a simple linear regression over recent points to classify the direction of change.
    var trendDirection: TrendDirection {
        guard chartData.count >= 3 else { return .stable }
        let times = chartData.map { Double($0.timeMs) }
        guard let slope = leastSquaresSlope(times) else { return .stable }
        if slope < InsightThresholds.improvingSlopeMs { return .improving }
        if slope > InsightThresholds.decliningSlopeMs { return .declining }
        return .stable
    }

    var body: some View {
        if chartData.count < 2 {
            Text("Need 2+ practices to show trend")
                .font(.caption)
                .foregroundStyle(Color.readableSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                // Trend badge
                HStack {
                    Spacer()
                    TrendBadge(direction: trendDirection)
                }

                Chart {
                    // Practice and regatta results share the line, but use different point symbols.
                    ForEach(Array(chartData.enumerated()), id: \.offset) { index, point in
                        LineMark(
                            x: .value("Practice", index),
                            y: .value("Time (ms)", point.timeMs)
                        )
                        .foregroundStyle(Color.readableBlue)
                        .accessibilityLabel("\(point.source == .practice ? "Practice" : "Regatta") result \(index + 1) of \(chartData.count)")
                        .accessibilityValue(formatMillisecondsForDisplay(point.timeMs))

                        if point.source == .practice {
                            PointMark(
                                x: .value("Practice", index),
                                y: .value("Time (ms)", point.timeMs)
                            )
                            .foregroundStyle(Color.readableBlue)
                            .symbol(.circle)
                            .accessibilityHidden(true)
                        } else {
                            PointMark(
                                x: .value("Practice", index),
                                y: .value("Time (ms)", point.timeMs)
                            )
                            .foregroundStyle(Color.readablePurple)
                            .symbol(.diamond)
                            .symbolSize(70)
                            .accessibilityHidden(true)
                        }
                    }

                    // The personal-best rule gives quick context without requiring axis labels.
                    if let pb = personalBestMs {
                        RuleMark(y: .value("PB", pb))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4]))
                            .foregroundStyle(Color.readableYellow)
                            .accessibilityLabel("Personal best")
                            .accessibilityValue(formatMillisecondsForDisplay(pb))
                            .annotation(position: .trailing) {
                                Text("PB")
                                    .font(.system(size: chartLabelSize))
                                    .foregroundStyle(Color.readableYellow)
                            }
                    }
                }
                .chartYScale(domain: chartYDomain)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let ms = value.as(Int.self) {
                                Text(formatMillisecondsCoarse(ms))
                                    .font(.system(size: chartLabelSize))
                            }
                        }
                    }
                }
                .frame(height: 120)
            }
        }
    }

    var chartYDomain: ClosedRange<Int> {
        let times = chartData.map { $0.timeMs }
        let minVal = max((times.min() ?? 0) - 2000, 0)
        let maxVal = (times.max() ?? 10000) + 2000
        return minVal...maxVal
    }

}

/// Identifies the source of a point in the trend chart.
enum TrendSource {
    case practice
    case regatta
}

/// Normalized data used to draw the performance trend chart.
struct TrendDataPoint {
    let date: Date
    let timeMs: Int
    let source: TrendSource
}

// MARK: - Fitness Tests

/// Highlights the most recent result for each supported fitness test.
struct FitnessTestsSummarySection: View {
    let athlete: Athlete

    var latestByTestType: [FitnessTestResult] {
        fitnessTestTypes.compactMap { testType in
            (athlete.fitnessTestResults ?? [])
                .filter { $0.testType == testType }
                .max { lhs, rhs in
                    if lhs.testDate == rhs.testDate {
                        return lhs.createdAt < rhs.createdAt
                    }
                    return lhs.testDate < rhs.testDate
                }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Fitness Tests")
                Spacer()
                // Sketch G: when empty, the link reads as the add action — the
                // test screen is where results get logged. No stub text row.
                NavigationLink(destination: FitnessTestView(athlete: athlete)) {
                    Text(latestByTestType.isEmpty ? "Add" : "View All")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }

            if !latestByTestType.isEmpty {
                VStack(spacing: 8) {
                    ForEach(latestByTestType) { result in
                        FitnessTestSummaryRow(athlete: athlete, result: result)
                    }
                }
                if athlete.gender == nil {
                    Text("Set athlete gender to see LTAD benchmarks.")
                        .font(.caption)
                        .foregroundStyle(Color.readableSecondary)
                }
            }
        }
    }
}

/// Summary row showing the latest result against the athlete's benchmark when available.
struct FitnessTestSummaryRow: View {
    let athlete: Athlete
    let result: FitnessTestResult

    var benchmarkSeconds: Double? {
        ltadBenchmarkSeconds(for: athlete, testType: result.testType)
    }

    var benchmarkPercent: Double? {
        guard let benchmarkSeconds, benchmarkSeconds > 0 else { return nil }
        return (result.result / benchmarkSeconds) * 100
    }

    var percentColor: Color {
        guard let benchmarkPercent else { return .secondary }
        let away = max(0, benchmarkPercent - 100)
        if away <= 10 { return .green }
        if away <= 25 { return .orange }
        return .red
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(result.testType)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(result.formattedTime)
                    .font(.caption)
                    .foregroundStyle(Color.readableSecondary)
            }

            Spacer()

            if let benchmarkPercent {
                Text(String(format: "%.1f%%", benchmarkPercent))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(percentColor)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(Color.readableSecondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Regatta Results

/// Shows the athlete's most recent regatta results and links to the full race history.
struct RegattaResultsSection: View {
    let athlete: Athlete

    var recentResults: [RegattaResult] {
        (athlete.regattaResults ?? [])
            .sorted { lhs, rhs in
                if lhs.regattaDate == rhs.regattaDate {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.regattaDate > rhs.regattaDate
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Regatta Results")
                Spacer()
                NavigationLink(destination: RegattaResultsView(athlete: athlete)) {
                    Text("View All")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }

            if recentResults.isEmpty {
                Text("No regatta results logged yet")
                    .font(.subheadline)
                    .foregroundStyle(Color.readableSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(recentResults.prefix(3)) { result in
                        RegattaProfileRow(result: result)
                    }
                }
            }
        }
    }
}

/// Compact regatta result row used in the profile summary list.
struct RegattaProfileRow: View {
    let result: RegattaResult

    var placementText: String? {
        guard let placement = result.placement else { return nil }
        if let total = result.totalCompetitors {
            return "\(String.ordinal(placement)) of \(total)"
        }
        return String.ordinal(placement)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(result.regattaName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text("\(String(result.eventDistance))m")
                        .font(.caption)
                        .foregroundStyle(Color.readableSecondary)
                    if let placementText {
                        Text("• \(placementText)")
                            .font(.caption)
                            .foregroundStyle(Color.readableSecondary)
                    }
                }
            }
            Spacer()
            Text(result.formattedTime)
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Trend Badge

/// High-level trend categories derived from recent timed results.
enum TrendDirection {
    case improving, stable, declining
}

/// Small visual summary of a computed performance trend.
struct TrendBadge: View {
    let direction: TrendDirection

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    var icon: String {
        switch direction {
        case .improving: return "arrow.down"
        case .stable:    return "minus"
        case .declining: return "arrow.up"
        }
    }

    var label: String {
        switch direction {
        case .improving: return "Improving"
        case .stable:    return "Stable"
        case .declining: return "Needs Attention"
        }
    }

    var color: Color {
        switch direction {
        case .improving: return .green
        case .stable:    return .gray
        case .declining: return .red
        }
    }
}

// MARK: - Load Section

/// Summarizes weekly and seasonal training load against LTAD guidance.
///
/// Recovery-zone distance is intentionally excluded so the load total better reflects work
/// that should count toward progression targets.
struct LoadSection: View {
    let athlete: Athlete

    /// LTAD yearly km target range for this athlete's age category.
    var ltadTarget: (min: Double, max: Double) {
        SeasonContext.ltadKmTarget(for: athlete.ageCategory)
    }

    /// Completed sessions the athlete attended, deduplicated by session id.
    /// Completed-only matches the team load definition — open or cancelled
    /// practices must not feed LTAD progress. The dedupe guards against
    /// CloudKit sync leaving duplicate attendance records for one session,
    /// which would otherwise double-count its km.
    private var attendedCompletedSessions: [CoachSession] {
        var seen = Set<UUID>()
        return (athlete.attendanceRecords ?? [])
            .filter { $0.status == .present }
            .compactMap { $0.session }
            .filter { $0.status == .completed && seen.insert($0.id).inserted }
    }

    var seasonalKm: Double {
        let attendedSessions = attendedCompletedSessions
            .filter { SeasonContext.contains($0.scheduledDate) }
        return SeasonContext.loadKilometers(from: attendedSessions)
    }

    /// On-water block types — the only km that count toward LTAD progress.
    private static let paddleBlockTypes: Set<BlockType> = [
        .paddleDistance, .paddleTimePieces, .paddlePyramid
    ]

    /// Paddling km this season. The CKC LTAD km targets are on-water volumes,
    /// so the progress bar compares against this rather than `seasonalKm` —
    /// a 5 km run still counts toward the headline load totals but must not
    /// advance a paddler's LTAD bar.
    var seasonalPaddleKm: Double {
        attendedCompletedSessions
            .filter { SeasonContext.contains($0.scheduledDate) }
            .flatMap { $0.sessionBlocks ?? [] }
            .filter { Self.paddleBlockTypes.contains($0.blockType) && $0.trainingZone != .recovery }
            .compactMap(\.effectiveDistanceKm)
            .reduce(0, +)
    }

    var weeklyKm: Double {
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recentSessions = attendedCompletedSessions
            .filter { $0.scheduledDate >= oneWeekAgo }
        return SeasonContext.loadKilometers(from: recentSessions)
    }

    /// km per zone this season (excluding recovery), omitting zones with zero km.
    var seasonalZoneBreakdown: [(zone: TrainingZone, km: Double)] {
        let blocks = attendedCompletedSessions
            .filter { SeasonContext.contains($0.scheduledDate) }
            .flatMap { $0.sessionBlocks ?? [] }
            .filter { $0.trainingZone != .recovery }
        let zones: [TrainingZone] = [.ga1, .ga2, .e1, .e2, .anMix, .alactic]
        return zones.compactMap { zone in
            let km = blocks
                .filter { $0.trainingZone == zone }
                .compactMap { $0.effectiveDistanceKm }
                .reduce(0, +)
            return km > 0 ? (zone, km) : nil
        }
    }

    var progress: Double {
        min(seasonalPaddleKm / ltadTarget.max, 1.0)
    }

    var progressColor: Color {
        if seasonalPaddleKm < ltadTarget.min * 0.5 { return .red }
        if seasonalPaddleKm < ltadTarget.min        { return .orange }
        if seasonalPaddleKm <= ltadTarget.max        { return .green }
        return .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Training Load")

            // Weekly and seasonal stats
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text(String(format: "%.1f", weeklyKm))
                        .font(.title2).fontWeight(.bold)
                        .foregroundStyle(Color.accentColor)
                    Text("km this week")
                        .font(.caption)
                        .foregroundStyle(Color.readableSecondary)
                }
                VStack(spacing: 4) {
                    Text(String(format: "%.0f", seasonalKm))
                        .font(.title2).fontWeight(.bold)
                        .foregroundStyle(progressColor)
                    Text("km this season")
                        .font(.caption)
                        .foregroundStyle(Color.readableSecondary)
                }
                Spacer()
            }

            // Progress bar toward LTAD target
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("LTAD Target (\(athlete.ageCategory))")
                        .font(.caption)
                        .foregroundStyle(Color.readableSecondary)
                    Spacer()
                    Text("\(String(Int(ltadTarget.min)))–\(String(Int(ltadTarget.max))) km/year")
                        .font(.caption)
                        .foregroundStyle(Color.readableSecondary)
                }

                if seasonalPaddleKm == 0 {
                    Text("No paddling km logged this season")
                        .font(.subheadline)
                        .foregroundStyle(Color.readableSecondary)
                } else {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.15))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(progressColor)
                                .frame(width: geo.size.width * progress, height: 8)

                            // Min target marker
                            let minX = geo.size.width * (ltadTarget.min / ltadTarget.max)
                            Rectangle()
                                .fill(Color.secondary.opacity(0.5))
                                .frame(width: 1.5, height: 12)
                                .offset(x: minX, y: -2)
                        }
                    }
                    .frame(height: 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Training load progress")
                    .accessibilityValue("\(loadStatusLabel), \(Int(progress * 100)) percent of annual target")
                }

                if seasonalPaddleKm > 0 {
                    // Status label
                    HStack {
                        Text("Status: \(loadStatusLabel)")
                            .font(.caption2)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(String(format: "%.0f%%", progress * 100))
                            .font(.caption2)
                            .foregroundStyle(Color.readableSecondary)
                    }
                }
            }

            if !seasonalZoneBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Season km by zone")
                        .font(.caption)
                        .foregroundStyle(Color.readableSecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(seasonalZoneBreakdown, id: \.zone) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.zone.rawValue)
                                        .font(.caption2).fontWeight(.semibold)
                                        .foregroundStyle(item.zone.color)
                                    Text(item.zone.description)
                                        .font(.caption2).foregroundStyle(Color.readableSecondary)
                                        .lineLimit(2)
                                    Text(String(format: "%.1f km", item.km))
                                        .font(.caption).foregroundStyle(.primary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(item.zone.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(item.zone.rawValue), \(String(format: "%.1f", item.km)) km")
                            }
                        }
                    }
                }
            }

            Text("Recovery zone km excluded from load totals. LTAD progress counts paddling km only — runs don't advance it.")
                .font(.caption2)
                .foregroundStyle(Color.readableSecondary)
        }
    }

    var loadStatusLabel: String {
        if seasonalPaddleKm == 0        { return "No km logged yet" }
        if seasonalPaddleKm < ltadTarget.min * 0.5 { return "Well below target range" }
        if seasonalPaddleKm < ltadTarget.min        { return "Below target range" }
        if seasonalPaddleKm <= ltadTarget.max       { return "On track ✓" }
        return "Above target range"
    }
}

// MARK: - Insight Section

/// Surfaces compact coach-facing alerts based on recent attendance and performance history.
///
/// This V1 section intentionally limits itself to two explainable signals so the profile stays
/// readable and the reasoning behind each alert is obvious to the coach.
struct AthleteInsightSection: View {
    let athlete: Athlete

    // The actual signal math lives in InsightSignals.swift — these are thin
    // wrappers so the body markup below stays unchanged and the underlying
    // math is unit-testable without SwiftUI.
    var decliningBlock: String?                                  { athlete.decliningBlockName }
    var inconsistentPacingBlock: (name: String, cvPercent: Int)? { athlete.inconsistentPacingBlock }
    var mostImprovedBlock: String?                                { athlete.mostImprovedBlockName }
    var ktcDecliningCount: Int?                                   { athlete.ktcDecliningCount }

    var hasNegativeInsights: Bool {
        decliningBlock != nil || inconsistentPacingBlock != nil || ktcDecliningCount != nil
    }

    var hasInsights: Bool {
        hasNegativeInsights || mostImprovedBlock != nil
    }

    var cardAccentColor: Color {
        hasNegativeInsights ? .orange : .green
    }

    var body: some View {
        if hasInsights {
            VStack(alignment: .leading, spacing: 10) {
                Text("Insights")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 8) {
                    if let blockName = mostImprovedBlock {
                        NavigationLink(destination: BlockTrendDetailView(blockName: blockName, athlete: athlete)) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down.right")
                                    .font(.caption)
                                    .foregroundStyle(Color.readableGreen)
                                Text("\(blockName): improving")
                                    .font(.subheadline)
                                Spacer()
                                TrendBadge(direction: .improving)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(Color.readableSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if let blockName = decliningBlock {
                        NavigationLink(destination: BlockTrendDetailView(blockName: blockName, athlete: athlete)) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(Color.readableRed)
                                Text("\(blockName): declining")
                                    .font(.subheadline)
                                Spacer()
                                TrendBadge(direction: .declining)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(Color.readableSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if let pacing = inconsistentPacingBlock {
                        NavigationLink(destination: BlockTrendDetailView(blockName: pacing.name, athlete: athlete)) {
                            HStack(spacing: 8) {
                                Image(systemName: "waveform.path.ecg")
                                    .font(.caption)
                                    .foregroundStyle(Color.readableOrange)
                                Text("\(pacing.name): erratic pacing (\(pacing.cvPercent)% CV)")
                                    .font(.subheadline)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(Color.readableSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if let count = ktcDecliningCount {
                        HStack(spacing: 8) {
                            Image(systemName: "chart.line.downtrend.xyaxis")
                                .font(.caption)
                                .foregroundStyle(Color.readableRed)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("KTC trend declining")
                                    .font(.subheadline)
                                Text("Average KTC score has decreased over the last \(count) assessments.")
                                    .font(.caption)
                                    .foregroundStyle(Color.readableSecondary)
                            }
                            Spacer()
                            TrendBadge(direction: .declining)
                        }
                    }
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(cardAccentColor.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

// MARK: - Block Trend Detail

/// Full-screen destination for an insight row — shows the block's performance card and chart.
struct BlockTrendDetailView: View {
    let blockName: String
    let athlete: Athlete

    var records: [PerformanceRecord] {
        (athlete.performanceRecords ?? [])
            .filter { $0.sessionBlock?.blockName == blockName && $0.status == .complete }
            .sorted { ($0.sessionBlock?.session?.scheduledDate ?? .distantPast) > ($1.sessionBlock?.session?.scheduledDate ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            PerformanceBlockCard(blockName: blockName, records: records, athlete: athlete)
                .padding()
        }
        .navigationTitle(blockName)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

// MARK: - Technical Summary

/// Summarizes the athlete's current technical stage and latest assessment snapshot.
struct TechnicalSummarySection: View {
    let athlete: Athlete

    @State private var showingNewAssessment = false

    private var latestAssessment: TechnicalAssessment? {
        (athlete.technicalAssessments ?? []).max { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.date < rhs.date
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Sketch G: with no assessments the full stage card collapses to a
            // single header row with an inline Add action.
            if let latestAssessment {
                SectionHeader(title: "Technical")

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Current Stage")
                            .font(.subheadline)
                            .foregroundStyle(Color.readableSecondary)
                        Spacer()
                        DevelopmentStagePill(stage: athlete.developmentStage)
                    }

                    HStack {
                        Text("Most recent")
                            .font(.subheadline)
                            .foregroundStyle(Color.readableSecondary)
                        Spacer()
                        Text(latestAssessment.date.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(.subheadline)
                    }

                    HStack {
                        Text("Average score")
                            .font(.subheadline)
                            .foregroundStyle(Color.readableSecondary)
                        Spacer()
                        Text(String(format: "%.2f / 5", latestAssessment.averageScore))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    HStack(spacing: 10) {
                        NavigationLink(destination: TechnicalAssessmentView(athlete: athlete)) {
                            Text("View All")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)

                        Button("New Assessment") {
                            showingNewAssessment = true
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else {
                HStack {
                    SectionHeader(title: "Technical")
                    Spacer()
                    Button {
                        showingNewAssessment = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.caption).fontWeight(.semibold)
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewAssessment) {
            NewAssessmentView(athlete: athlete)
#if os(macOS)
                .frame(minWidth: 720, minHeight: 760)
#endif
        }
    }
}

// MARK: - Notes Section

/// Groups coach notes by session so recent feedback can be scanned quickly on the profile.
struct NotesSection: View {
    let athlete: Athlete
    @State private var showingAllSessions = false

    /// Collapses multiple notes from the same session into a single card for the profile view.
    var groupedNotes: [SessionNoteGroup] {
        let groups = Dictionary(grouping: athlete.notes ?? []) { note -> UUID in
            note.session?.id ?? note.id
        }

        return groups.compactMap { _, notes in
            guard let first = notes.first else { return nil }
            let session = first.session
            let sessionDate = session?.scheduledDate ?? first.createdAt
            let sorted = notes.sorted { $0.createdAt > $1.createdAt }
            return SessionNoteGroup(
                id: session?.id ?? first.id,
                sessionName: session?.sessionName ?? "Practice Note",
                sessionDate: sessionDate,
                notes: sorted
            )
        }
        .sorted { $0.sessionDate > $1.sessionDate }
    }

    var visibleGroups: [SessionNoteGroup] {
        if showingAllSessions {
            return groupedNotes
        }
        return Array(groupedNotes.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Coach Notes")
                Spacer()
                Text("\(groupedNotes.count) practice\(groupedNotes.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Color.readableSecondary)
            }

            if groupedNotes.isEmpty {
                Text("No notes recorded yet")
                    .font(.subheadline)
                    .foregroundStyle(Color.readableSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(visibleGroups) { group in
                        SessionNotesCard(group: group)
                    }
                }

                if groupedNotes.count > 3 {
                    Button(showingAllSessions ? "Show Less" : "Show More") {
                        withAnimation(.smooth) {
                            showingAllSessions.toggle()
                        }
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

/// View model for session-scoped note cards on the athlete profile.
struct SessionNoteGroup: Identifiable {
    let id: UUID
    let sessionName: String
    let sessionDate: Date
    let notes: [AthleteNote]
}

/// Card showing all coach notes captured for a single session.
struct SessionNotesCard: View {
    let group: SessionNoteGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(group.sessionName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(group.sessionDate.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.caption)
                    .foregroundStyle(Color.readableSecondary)
            }

            Divider()

            ForEach(group.notes) { note in
                NoteRow(note: note, sessionDate: group.sessionDate)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Displays a single coach note with its session and block context.
struct NoteRow: View {
    let note: AthleteNote
    let sessionDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.noteText)
                .font(.subheadline)

            HStack(spacing: 8) {
                Text(sessionDate.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.caption)
                    .foregroundStyle(Color.readableSecondary)

                if let block = note.sessionBlock {
                    Text("• \(block.blockName)")
                        .font(.caption)
                        .foregroundStyle(Color.readableSecondary)

                    if let zone = block.trainingZone {
                        TrainingZonePill(zone: zone)
                    }
                }
            }

            LoggedByLabel(coachName: note.createdByCoachName)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Compact zone badge used beside note context when a note belongs to a workout block.
struct TrainingZonePill: View {
    let zone: TrainingZone

    var body: some View {
        Text(zone.rawValue)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(zone.color.opacity(0.15))
            .foregroundStyle(zone.color)
            .clipShape(Capsule())
    }
}

// MARK: - Development Focus Panel

/// Returns the predefined journal tags whose name appears as a case-insensitive
/// substring of the rating's factor or category. Mirrors the matching rule used
/// by `Athlete.developmentCoverage()` so a note pre-tagged from a focus-area row
/// will be picked up as covering that gap. The tags (catch/exit/draw/balance/…)
/// are category themes, so the category is where most matches come from — a
/// factor like "Position and posture in boat" matches via its "Balance Set-Up"
/// category. Returns an empty set if no predefined tag matches — the coach can
/// then pick tags manually.
fileprivate func matchingPredefinedTags(for rating: TechnicalRating) -> Set<String> {
    // Shared rule (TechnicalRating.matchesDevelopmentTag) — the same one
    // Athlete.developmentCoverage() counts with, so the two can't drift.
    Set(developmentNoteTags.filter { rating.matchesDevelopmentTag($0) })
}

/// Identifiable payload for presenting `AddDevelopmentNoteSheet` from a
/// focus-area row. `id` is a fresh UUID per request so re-tapping the same
/// row reopens the sheet cleanly.
fileprivate struct DevelopmentNoteSheetRequest: Identifiable {
    let id = UUID()
    let initialTags: Set<String>
}

/// Auto-derives focus areas and strengths from the athlete's most recent technical assessment.
struct DevelopmentFocusPanel: View {
    let athlete: Athlete

    @State private var noteRequest: DevelopmentNoteSheetRequest? = nil

    /// Focus-area gaps with per-area coverage status. Each entry wraps a
    /// score-≤2 TechnicalRating plus how many DevelopmentNotes inside the
    /// coverage window carry a matching tag.
    private var coverage: [DevelopmentCoverage] {
        athlete.developmentCoverage()
    }

    private var strengths: [TechnicalRating] {
        (athlete.latestTechnicalAssessment?.ratings ?? [])
            .filter { $0.score >= 4 }
            .sorted { $0.category < $1.category }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Sketch G: empty states collapse to a single header row with a
            // trailing hint. The panel derives from assessments, so the "add"
            // action lives on the Technical section above it.
            if athlete.latestTechnicalAssessment == nil {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: "Development Focus")
                    Spacer()
                    Text("Needs a technical assessment")
                        .font(.caption).foregroundStyle(Color.readableSecondary)
                }
            } else if coverage.isEmpty && strengths.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: "Development Focus")
                    Spacer()
                    Text("No factors scored ≤ 2 or ≥ 4")
                        .font(.caption).foregroundStyle(Color.readableSecondary)
                }
            } else {
                SectionHeader(title: "Development Focus")

                VStack(alignment: .leading, spacing: 12) {
                    if !coverage.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Focus Areas")
                                .font(.caption).fontWeight(.semibold).foregroundStyle(Color.readableOrange)
                            VStack(spacing: 5) {
                                ForEach(coverage) { entry in
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.rating.factor)
                                                .font(.caption).fontWeight(.semibold)
                                            Text(entry.rating.category)
                                                .font(.caption2).foregroundStyle(Color.readableSecondary)
                                            coverageSubtitle(for: entry)
                                        }
                                        Spacer()
                                        Text("\(entry.rating.score)/5")
                                            .font(.caption).fontWeight(.bold).foregroundStyle(Color.readableOrange)
                                        Button {
                                            noteRequest = DevelopmentNoteSheetRequest(
                                                initialTags: matchingPredefinedTags(for: entry.rating)
                                            )
                                        } label: {
                                            Image(systemName: "note.text.badge.plus")
                                                .font(.subheadline)
                                                .foregroundStyle(Color.readableOrange)
                                                .frame(width: 44, height: 44)  // HIG minimum tap target
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Add journal note for \(entry.rating.factor)")
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }

                    if !strengths.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Strengths")
                                .font(.caption).fontWeight(.semibold).foregroundStyle(Color.readableGreen)
                            VStack(spacing: 5) {
                                ForEach(strengths) { rating in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(rating.factor)
                                                .font(.caption).fontWeight(.semibold)
                                            Text(rating.category)
                                                .font(.caption2).foregroundStyle(Color.readableSecondary)
                                        }
                                        Spacer()
                                        Text("\(rating.score)/5")
                                            .font(.caption).fontWeight(.bold).foregroundStyle(Color.readableGreen)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                }

                if let date = athlete.latestTechnicalAssessment?.date {
                    Text("From assessment \(date.formatted(.dateTime.month(.abbreviated).day().year()))")
                        .font(.caption2).foregroundStyle(Color.readableSecondary)
                }
            }
        }
        .sheet(item: $noteRequest) { request in
            AddDevelopmentNoteSheet(athlete: athlete, initialTags: request.initialTags)
#if os(macOS)
                .frame(minWidth: 480, minHeight: 520)
#endif
        }
    }

    /// Coverage hint beneath each focus-area card. Recent matching notes is
    /// informational; zero is the "uncovered gap" signal in orange italic.
    @ViewBuilder
    private func coverageSubtitle(for entry: DevelopmentCoverage) -> some View {
        if entry.isCovered {
            Text("💬 \(entry.noteCount) \(entry.noteCount == 1 ? "note" : "notes") in last \(InsightThresholds.coverageWindowDays)d")
                .font(.caption2).foregroundStyle(Color.readableSecondary)
        } else {
            Text("⚠ No recent notes — uncovered")
                .font(.caption2).italic()
                .foregroundStyle(.orange.opacity(0.9))
        }
    }
}

// MARK: - KTC Scores

/// Lists KTC assessment snapshots and allows adding new ones.
struct KTCScoresSection: View {
    @Bindable var athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddKTC = false

    var sortedAssessments: [KTCAssessment] {
        (athlete.ktcAssessments ?? []).sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: "KTC Scores")
                Spacer()
                Button {
                    showingAddKTC = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.caption).fontWeight(.semibold)
                }
            }

            // Sketch G: when empty, the header row with its Add button is the
            // whole section.
            if !sortedAssessments.isEmpty {
                VStack(spacing: 8) {
                    ForEach(sortedAssessments) { assessment in
                        KTCAssessmentRow(assessment: assessment)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddKTC) {
            AddKTCAssessmentSheet(athlete: athlete)
        }
    }
}

/// Row showing one KTC snapshot: window, date, average, and 4-phase breakdown.
struct KTCAssessmentRow: View {
    let assessment: KTCAssessment
    @Environment(\.modelContext) private var modelContext
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(assessment.window)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(assessment.date.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(.caption)
                        .foregroundStyle(Color.readableSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f / 5", assessment.averageScore))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("avg")
                        .font(.caption2)
                        .foregroundStyle(Color.readableSecondary)
                }
            }

            HStack(spacing: 0) {
                KTCPhaseScore(label: "Setup", score: assessment.setupRecoveryScore)
                Spacer()
                Text("·").font(.caption2).foregroundStyle(Color.readableSecondary)
                Spacer()
                KTCPhaseScore(label: "Catch", score: assessment.catchScore)
                Spacer()
                Text("·").font(.caption2).foregroundStyle(Color.readableSecondary)
                Spacer()
                KTCPhaseScore(label: "Prop", score: assessment.propulsionDrawScore)
                Spacer()
                Text("·").font(.caption2).foregroundStyle(Color.readableSecondary)
                Spacer()
                KTCPhaseScore(label: "Exit", score: assessment.exitScore)
            }

            if let notes = assessment.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(Color.readableSecondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        // No .swipeActions here — these rows live in a ScrollView, not a List,
        // where swipe actions silently do nothing. The context menu is the
        // delete affordance (long-press on iOS, right-click on Mac).
        .contextMenu {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog("Delete this KTC assessment?",
                            isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteAssessment() }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Save Error", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
    }

    private func deleteAssessment() {
        modelContext.delete(assessment)
        do {
            try SyncStore.save(modelContext)
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }
}

/// Compact score chip for one KTC phase.
struct KTCPhaseScore: View {
    let label: String
    let score: Int

    var scoreColor: Color {
        switch score {
        case 1, 2: return .orange
        case 4, 5: return .green
        default:   return .secondary
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.readableSecondary)
            Text("\(score)/5")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(scoreColor)
        }
    }
}

/// Sheet for logging a new KTC assessment for an athlete.
struct AddKTCAssessmentSheet: View {
    let athlete: Athlete

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedWindow = ""
    @State private var date = Date()
    @State private var setupScore = 3
    @State private var catchScore = 3
    @State private var propulsionScore = 3
    @State private var exitScore = 3
    @State private var notes = ""
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""

    var isValid: Bool {
        !selectedWindow.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Assessment Window") {
                    Picker("Window", selection: $selectedWindow) {
                        Text("Select…").tag("")
                        ForEach(ktcWindows, id: \.self) { window in
                            Text(window).tag(window)
                        }
                    }
                    DatePicker("Date", selection: $date, in: ...Date.now,
                               displayedComponents: .date)
                }

                Section("Phase Scores (1–5)") {
                    Stepper("Setup / Recovery: \(setupScore)", value: $setupScore, in: 1...5)
                    Stepper("Catch: \(catchScore)", value: $catchScore, in: 1...5)
                    Stepper("Propulsion / Draw: \(propulsionScore)", value: $propulsionScore, in: 1...5)
                    Stepper("Exit: \(exitScore)", value: $exitScore, in: 1...5)
                }

                Section("Notes (optional)") {
                    TextField("Observations…", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add KTC Assessment")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                        .fontWeight(.semibold)
                }
            }
            .alert("Couldn't Save", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
    }

    private func save() {
        let assessment = KTCAssessment(
            date: date,
            window: selectedWindow,
            setupRecoveryScore: setupScore,
            catchScore: catchScore,
            propulsionDrawScore: propulsionScore,
            exitScore: exitScore,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : notes.trimmingCharacters(in: .whitespacesAndNewlines),
            athlete: athlete
        )
        modelContext.insert(assessment)
        do {
            try SyncStore.save(modelContext)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showingSaveError = true
        }
    }
}

// MARK: - Development Journal

/// The 10 predefined journal topic tags offered when writing a development note.
/// Kept in sync with the tag-matching rule in `matchingPredefinedTags(for:)`.
private let developmentNoteTags: [String] = [
    "catch", "exit", "draw", "balance", "boat-control",
    "fitness", "mental", "race-prep", "technique", "goal"
]

/// Freeform coaching journal — dated entries with optional topic tags.
struct DevelopmentJournalSection: View {
    @Bindable var athlete: Athlete
    @State private var showingAddNote = false

    var sortedNotes: [DevelopmentNote] {
        (athlete.developmentNotes ?? []).sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: "Development Journal")
                Spacer()
                Button {
                    showingAddNote = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.caption).fontWeight(.semibold)
                }
            }

            // Sketch G: when empty, the header row with its Add button is the
            // whole section.
            if !sortedNotes.isEmpty {
                VStack(spacing: 8) {
                    ForEach(sortedNotes) { note in
                        DevelopmentNoteCard(note: note)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddNote) {
            AddDevelopmentNoteSheet(athlete: athlete)
        }
    }
}

/// Card for a single development-journal entry: date, text, topic tags, and a
/// context-menu delete (no swipe — these rows live in a ScrollView, not a List).
struct DevelopmentNoteCard: View {
    let note: DevelopmentNote
    @Environment(\.modelContext) private var modelContext
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.date.formatted(.dateTime.month(.abbreviated).day().year()))
                .font(.caption).foregroundStyle(Color.readableSecondary)

            Text(note.text)
                .font(.subheadline)

            if !note.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(note.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2).fontWeight(.semibold)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            LoggedByLabel(coachName: note.createdByCoachName)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog("Delete this journal entry?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { modelContext.delete(note) }
            Button("Cancel", role: .cancel) { }
        }
    }
}

/// Sheet for adding a development-journal entry. Optionally pre-seeds topic tags
/// (e.g. when launched from a focus-area row) so the note lands tagged to the gap.
struct AddDevelopmentNoteSheet: View {
    let athlete: Athlete

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var selectedTags: Set<String>
    @State private var date = Date()
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""

    // Custom init so `selectedTags` can be seeded from `initialTags` without
    // an onAppear flicker. Mirrors the pattern in `AddBlockSheet`.
    init(athlete: Athlete, initialTags: Set<String> = []) {
        self.athlete = athlete
        _selectedTags = State(initialValue: initialTags)
    }

    var isValid: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                }

                Section("Note") {
                    TextField("Observations, goals, focus areas…", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                }

                Section("Tags (optional)") {
                    FlowLayout(spacing: 8) {
                        ForEach(developmentNoteTags, id: \.self) { tag in
                            let selected = selectedTags.contains(tag)
                            Button {
                                if selected { selectedTags.remove(tag) }
                                else { selectedTags.insert(tag) }
                            } label: {
                                Text("#\(tag)")
                                    .font(.caption).fontWeight(.semibold)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(
                                        selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Journal Entry")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
            .alert("Couldn't Save", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let note = DevelopmentNote(
            date: date,
            text: trimmed,
            tags: Array(selectedTags).sorted(),
            athlete: athlete
        )
        note.createdByCoachName = CoachIdentity.currentName(in: modelContext)
        modelContext.insert(note)
        do {
            try SyncStore.save(modelContext)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showingSaveError = true
        }
    }
}

// MARK: - Flow Layout (wrapping tag layout)

/// A lightweight wrapping layout used for compact tag-like content such as team chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    /// Measures wrapped content height for the available width proposed by the parent.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width,
                                subviews: subviews, spacing: spacing)
        return result.size
    }

    /// Places subviews using the same wrapping calculation used during measurement.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX,
                                              y: bounds.minY + frame.minY),
                                  proposal: ProposedViewSize(frame.size))
        }
    }

    /// Cached wrapping result shared by measurement and placement so both use identical frames.
    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            var maxX: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth, x > 0 {
                    y += rowHeight + spacing
                    x = 0
                    rowHeight = 0
                }
                frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
                x += size.width + spacing
                rowHeight = max(rowHeight, size.height)
                maxX = max(maxX, x - spacing)
            }
            self.size = CGSize(width: maxX, height: y + rowHeight)
        }
    }
}

// MARK: - Height & Growth Section

/// Shows an athlete's height log and calculates growth velocity for PHV monitoring.
struct HeightGrowthSection: View {
    @Bindable var athlete: Athlete
    @State private var showingAddHeight = false

    var sortedHeights: [HeightRecord] {
        (athlete.heightRecords ?? []).sorted { $0.date > $1.date }
    }

    /// Minimum spacing between the two readings for a meaningful annualized
    /// velocity. Closer than ~2 months, ordinary measurement noise (±0.5 cm)
    /// annualizes into double-digit cm/year and fires false PHV flags; the
    /// CKC cadence is quarterly anyway.
    private static let minVelocityIntervalYears = 60.0 / 365.25

    /// Annualized growth velocity (cm/year) computed from the two most recent readings.
    var growthVelocity: Double? {
        guard sortedHeights.count >= 2 else { return nil }
        let latest   = sortedHeights[0]
        let previous = sortedHeights[1]
        let years = latest.date.timeIntervalSince(previous.date) / (365.25 * 86400)
        guard years >= Self.minVelocityIntervalYears else { return nil }
        return (latest.heightCm - previous.heightCm) / years
    }

    var isPHV: Bool {
        (growthVelocity ?? 0) >= SeasonContext.phvVelocityThresholdCmPerYear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: "Height & Growth")
                Spacer()
                Button {
                    showingAddHeight = true
                } label: {
                    Label("Log", systemImage: "plus")
                        .font(.caption).fontWeight(.semibold)
                }
            }

            // Sketch G: when empty, the header row with its Log button is the
            // whole section — no stub text, no cadence caption.
            if !sortedHeights.isEmpty {
                VStack(spacing: 8) {
                    ForEach(sortedHeights.prefix(4)) { record in
                        HStack {
                            Text(record.date.formatted(.dateTime.month(.abbreviated).day().year()))
                                .font(.caption)
                                .foregroundStyle(Color.readableSecondary)
                            Spacer()
                            Text(String(format: "%.1f cm", record.heightCm))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                if growthVelocity == nil && sortedHeights.count >= 2 {
                    Text("Last two measurements are under 2 months apart — too close together to estimate growth velocity.")
                        .font(.caption2)
                        .foregroundStyle(Color.readableSecondary)
                }

                if let velocity = growthVelocity {
                    HStack(spacing: 10) {
                        if isPHV {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.readableOrange)
                                .font(.subheadline)
                        } else {
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(Color.accentColor)
                                .font(.subheadline)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "%.1f cm/year growth velocity", velocity))
                                .font(.caption)
                                .fontWeight(.semibold)
                            if isPHV {
                                Text("Possible PHV — consider reducing training load")
                                    .font(.caption2)
                                    .foregroundStyle(Color.readableOrange)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        isPHV ? Color.orange.opacity(0.10) : Color.accentColor.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }

                Text("CKC requires 4 height measurements per year.")
                    .font(.caption2)
                    .foregroundStyle(Color.readableSecondary)
            }
        }
        .sheet(isPresented: $showingAddHeight) {
            AddHeightRecordSheet(athlete: athlete)
        }
    }
}

/// Collects a height measurement for an athlete.
struct AddHeightRecordSheet: View {
    let athlete: Athlete

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var heightText = ""
    @State private var date = Date()
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""

    var parsedHeight: Double? {
        let trimmed = heightText.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value > 50, value < 250 else { return nil }
        return value
    }

    var isValid: Bool { parsedHeight != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Height") {
                    HStack {
                        TextField("e.g. 165.5", text: $heightText)
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                        Text("cm")
                            .foregroundStyle(Color.readableSecondary)
                    }
                    if !heightText.isEmpty && parsedHeight == nil {
                        Text("Enter a height between 50 and 250 cm")
                            .font(.caption)
                            .foregroundStyle(Color.readableRed)
                    }
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                }
            }
            .navigationTitle("Log Height")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
            .alert("Couldn't Save", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
    }

    private func save() {
        guard let height = parsedHeight else { return }
        let record = HeightRecord(heightCm: height, date: date, athlete: athlete)
        modelContext.insert(record)
        do {
            try SyncStore.save(modelContext)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showingSaveError = true
        }
    }
}
