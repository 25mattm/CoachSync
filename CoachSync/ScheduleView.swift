/// Displays the seasonal calendar and the sessions scheduled for the selected day.

import SwiftUI
import SwiftData

/// Calendar-based session browser.
struct ScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    /// All non-archived sessions. The calendar can navigate to any month —
    /// including next year's — so the query must not be pinned to the year
    /// captured at view init (which also goes stale across a Jan 1 rollover
    /// while the app stays resident). Month/day scoping happens below.
    @Query(filter: #Predicate<CoachSession> { !$0.isArchived },
           sort: \CoachSession.scheduledDate)
    private var activeSessions: [CoachSession]
    @Query(sort: \RegattaResult.regattaDate) private var allRegattaResults: [RegattaResult]

    @State private var selectedDate = Date()
    @State private var showingAddSession = false
    @State private var sessionToLog: CoachSession? = nil
    @State private var displayedMonth = Date()
    @State private var sessionToEdit: CoachSession? = nil
    @State private var showingLogRegatta = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    @State private var deletionBlockedSession: CoachSession? = nil
    @State private var sessionToConfirmDelete: CoachSession? = nil

    /// Sessions in the visible month, used to draw calendar dots.
    var sessionsThisMonth: [CoachSession] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let start = calendar.date(from: components),
              let end = calendar.date(byAdding: .month, value: 1, to: start) else { return [] }
        return activeSessions.filter { $0.scheduledDate >= start && $0.scheduledDate < end }
    }

    /// Sessions on the currently selected day.
    var sessionsForSelectedDate: [CoachSession] {
        activeSessions.filter {
            Calendar.current.isDate($0.scheduledDate, inSameDayAs: selectedDate)
        }
    }

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Normalized day keys used to mark dates that contain at least one session.
    var datesWithSessions: Set<String> {
        Set(sessionsThisMonth.map { Self.dayKeyFormatter.string(from: $0.scheduledDate) })
    }

    /// Normalized day keys for dates that have at least one logged regatta result in the displayed month.
    var datesWithRegattas: Set<String> {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let start = calendar.date(from: components),
              let end = calendar.date(byAdding: .month, value: 1, to: start) else { return [] }
        return Set(
            allRegattaResults
                .filter { $0.regattaDate >= start && $0.regattaDate < end }
                .map { Self.dayKeyFormatter.string(from: $0.regattaDate) }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if activeSessions.isEmpty {
                    ScrollsWhenTooTall {
                        VStack(spacing: 14) {
                            Spacer()
                            Image(systemName: "calendar")
                                .font(.largeTitle)
                                .foregroundStyle(Color.readableSecondary)
                            Text("No practices scheduled")
                                .font(.headline)
                            Text("Archived practices are hidden from the calendar.")
                                .font(.subheadline)
                                .foregroundStyle(Color.readableSecondary)
                                .multilineTextAlignment(.center)
                            Button {
                                showingAddSession = true
                            } label: {
                                Label("Add Practice", systemImage: "plus")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(Color.accentColor.opacity(0.12))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 24)
                    }
                } else {
                    CalendarGridView(
                        selectedDate: $selectedDate,
                        displayedMonth: $displayedMonth,
                        datesWithSessions: datesWithSessions,
                        datesWithRegattas: datesWithRegattas
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                    Divider()

                    List {
                        Section {
                            Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                                .font(.headline)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)

                            if sessionsForSelectedDate.isEmpty {
                                EmptyCard(message: "No practices on this day",
                                          systemImage: "calendar.badge.plus")
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            } else {
                                ForEach(sessionsForSelectedDate) { session in
                                    Button { sessionToLog = session } label: {
                                        ScheduleSessionCard(session: session)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            sessionToEdit = session
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(Color.accentColor)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        if !session.isDeletable {
                                            Button {
                                                deletionBlockedSession = session
                                            } label: {
                                                Label("Can't Delete", systemImage: "exclamationmark.circle")
                                            }
                                            .tint(.gray)
                                        } else {
                                            Button(role: .destructive) {
                                                sessionToConfirmDelete = session
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                                    .contextMenu {
                                        Button {
                                            sessionToEdit = session
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        if !session.isDeletable {
                                            Button {
                                                deletionBlockedSession = session
                                            } label: {
                                                Label("Can't Delete", systemImage: "exclamationmark.circle")
                                            }
                                        } else {
                                            Button(role: .destructive) {
                                                sessionToConfirmDelete = session
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }

                            Button {
                                showingAddSession = true
                            } label: {
                                Label("Add Practice on This Day", systemImage: "plus")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.accentColor.opacity(0.12))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .padding(.top, 4)

                            Button {
                                showingLogRegatta = true
                            } label: {
                                Label("Log Regatta on This Day", systemImage: "flag.checkered")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.purple.opacity(0.1))
                                    .foregroundStyle(.purple)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Schedule")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        selectedDate = Date()
                        displayedMonth = Date()
                    } label: {
                        Text("Today")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showingAddSession) {
                AddSessionSheet(preselectedDate: selectedDate)
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
            .sheet(item: $sessionToEdit) { session in
                EditSessionSheet(session: session)
#if os(macOS)
                    .frame(minWidth: 520, minHeight: 560)
#endif
            }
            .sheet(isPresented: $showingLogRegatta) {
                LogRegattaSheet(preselectedDate: selectedDate)
#if os(macOS)
                    .frame(minWidth: 520, minHeight: 600)
#endif
            }
            .alert("Save Error", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
            .alert(item: $deletionBlockedSession) { session in
                Alert(
                    title: Text("Cannot Delete \"\(session.sessionName)\""),
                    message: Text("Completed sessions are permanently preserved. Archive the season in Settings to remove completed sessions from the schedule view."),
                    dismissButton: .default(Text("OK"))
                )
            }
            .confirmationDialog(
                "Delete \"\(sessionToConfirmDelete?.sessionName ?? "practice")\"?",
                isPresented: Binding(
                    get: { sessionToConfirmDelete != nil },
                    set: { if !$0 { sessionToConfirmDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Practice", role: .destructive) {
                    if let session = sessionToConfirmDelete { deleteSession(session) }
                    sessionToConfirmDelete = nil
                }
                Button("Cancel", role: .cancel) { sessionToConfirmDelete = nil }
            } message: {
                Text("This permanently deletes the practice along with its blocks, attendance, and any logged times.")
            }
        }
    }

    /// Deletes a session and surfaces persistence failures to the user.
    /// Uses the cascade helper because the schema's nullify rules don't
    /// auto-clean blocks / attendance / notes.
    private func deleteSession(_ session: CoachSession) {
        modelContext.deleteSessionCascade(session)
        do {
            try SyncStore.save(modelContext)
        } catch {
            saveErrorMessage = error.localizedDescription
            showingSaveError = true
        }
    }
}

// MARK: - Calendar Grid

/// Month grid with session indicators and selection state.
struct CalendarGridView: View {
    @Binding var selectedDate: Date
    @Binding var displayedMonth: Date
    let datesWithSessions: Set<String>
    let datesWithRegattas: Set<String>

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let daySymbols = Calendar.current.veryShortWeekdaySymbols

    private var monthDays: [Date?] {
        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: displayedMonth)
        ) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let leadingEmpties = firstWeekday - 1

        var days: [Date?] = Array(repeating: nil, count: leadingEmpties)
        for day in 0..<daysInMonth {
            if let date = calendar.date(byAdding: .day, value: day, to: monthStart) {
                days.append(date)
            }
        }
        return days
    }

    var body: some View {
        VStack(spacing: 8) {
            // Month navigation
            HStack {
                // `.buttonStyle(.plain)` is preventive, not currently load-bearing:
                // this HStack sits above the List today, so the adjacent-Button
                // mis-tap bug (see SessionLoggerView's Mark All Present fix) can't
                // occur yet — but it would the moment this view is ever embedded
                // in a List/Form row. Cheap to add now.
                Button {
                    advanceMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous month")

                Spacer()

                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)

                Spacer()

                Button {
                    advanceMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next month")
            }
            .padding(.vertical, 8)

            // Day of week headers
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(daySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.readableSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Day cells
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                    if let date = date {
                        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                        Button {
                            selectedDate = date
                        } label: {
                            DayCell(
                                date: date,
                                isSelected: isSelected,
                                isToday: calendar.isDateInToday(date),
                                hasSession: hasSession(on: date),
                                hasRegatta: hasRegatta(on: date)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
    }

    /// Uses the same normalized key format as `datesWithSessions`.
    private func hasSession(on date: Date) -> Bool {
        datesWithSessions.contains(Self.dayKeyFormatter.string(from: date))
    }

    private func hasRegatta(on date: Date) -> Bool {
        datesWithRegattas.contains(Self.dayKeyFormatter.string(from: date))
    }

    private func advanceMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }
}

// MARK: - Day Cell

/// Single day cell used by the schedule month grid.
struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasSession: Bool
    let hasRegatta: Bool

    var dayNumber: String {
        Calendar.current.component(.day, from: date).description
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 32, height: 32)
                } else if isToday {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 1.5)
                        .frame(width: 32, height: 32)
                }

                Text(dayNumber)
                    .font(.subheadline)
                    .fontWeight(isToday || isSelected ? .bold : .regular)
                    .foregroundStyle(isSelected ? .white : isToday ? Color.accentColor : .primary)
            }

            // Session and regatta dot indicators. Only render a dot when its
            // indicator is actually present — reserving space for a hidden
            // (.clear) dot on the other side pushed a lone dot off-center.
            HStack(spacing: 3) {
                if hasSession {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                }
                if hasRegatta {
                    // A diamond, so a regatta differs from a practice by more than color.
                    Rectangle()
                        .fill(Color.readableOrange)
                        .frame(width: 5, height: 5)
                        .rotationEffect(.degrees(45))
                }
            }
            .frame(height: 5)
            .accessibilityHidden(!hasSession && !hasRegatta)
        }
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var traits: [String] = []
        if isToday {
            traits.append("Today")
        }
        if isSelected {
            traits.append("Selected")
        }
        traits.append(hasSession ? "Has scheduled practices" : "No scheduled practices")
        if hasRegatta { traits.append("Has regatta results") }
        return traits.joined(separator: ", ")
    }
}

// MARK: - Schedule Session Card

/// Session summary card used in the day detail list.
struct ScheduleSessionCard: View {
    let session: CoachSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.sessionName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let team = session.team {
                        Text(team.teamName)
                            .font(.subheadline)
                            .foregroundStyle(Color.readableSecondary)
                    }
                }
                Spacer()
                StatusPill(status: session.status)
            }

            HStack(spacing: 16) {
                if let start = session.startTime, let end = session.endTime {
                    Label(
                        "\(start.formatted(.dateTime.hour().minute())) – \(end.formatted(.dateTime.hour().minute()))",
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundStyle(Color.readableSecondary)
                } else if let start = session.startTime {
                    Label(
                        start.formatted(.dateTime.hour().minute()),
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundStyle(Color.readableSecondary)
                }

                Label(
                    "\(session.team?.activeMembers.count ?? 0) athletes",
                    systemImage: "person.2"
                )
                .font(.caption)
                .foregroundStyle(Color.readableSecondary)
            }

            if let note = session.teamNote, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Color.readableSecondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background(
            Group {
                if #available(iOS 26, *) { Color.clear }
                else { RoundedRectangle(cornerRadius: 14).fill(.regularMaterial) }
            }
        )
        .ifAvailableiOS26 { $0.glassEffect(.regular, in: .rect(cornerRadius: 14)) }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(session.status.color.opacity(0.3), lineWidth: 1.5)
        )
    }
}
