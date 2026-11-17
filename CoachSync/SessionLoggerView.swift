/// Drives the multi-step workflow for recording attendance, block results, and completion data.

import SwiftUI
import SwiftData

/// Distinct screens in the session logging workflow.
enum LoggerPhase: Equatable {
    case attendance
    case blockEntry(Int)
    case summary
}

extension CoachSession {
    /// Attendance default for a roster athlete with no saved record. Open
    /// sessions default to present (the one-tap bulk-logging flow). Completed
    /// and cancelled sessions default to absent so merely reviewing an old
    /// practice cannot fabricate attendance — and with it practice history and
    /// training load — for athletes who joined the roster after it happened.
    var defaultAttendanceStatus: AttendanceStatus {
        status.isOpen ? .present : .absent
    }
}

/// Orchestrates the session logger flow for a single `CoachSession`.
struct SessionLoggerView: View {
    let session: CoachSession
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    /// Fallback athlete list used when the session is not scoped to a team.
    @Query(filter: #Predicate<Athlete> { $0.isActive }, sort: \Athlete.lastName)
    private var allAthletes: [Athlete]

    @State private var phase: LoggerPhase = .attendance
    /// In-memory attendance selections keyed by athlete ID until they are saved.
    @State private var attendanceMap: [UUID: AttendanceStatus] = [:]
    @State private var showingAddBlock = false
    @State private var showingEditSession = false
    @State private var isCompleting = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    /// Athletes visible for this session (team-scoped if present, otherwise all active).
    var sessionAthletes: [Athlete] {
        if let team = session.team {
            return team.activeMembers.sorted { $0.lastName < $1.lastName }
        }
        return allAthletes
    }

    /// Athletes currently marked present in the attendance map.
    var presentAthletes: [Athlete] {
        sessionAthletes.filter { (attendanceMap[$0.id] ?? session.defaultAttendanceStatus) == .present }
    }

    /// Session blocks sorted by `sortOrder`.
    var sortedBlocks: [SessionBlock] {
        (session.sessionBlocks ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .attendance:
                    AttendancePhaseView(
                        session: session,
                        athletes: sessionAthletes,
                        attendanceMap: $attendanceMap,
                        onDone: advanceFromAttendance
                    )
                case .blockEntry(let index):
                    if index < sortedBlocks.count {
                        BlockEntryPhaseView(
                            session: session,
                            block: sortedBlocks[index],
                            presentAthletes: presentAthletes,
                            blockIndex: index,
                            totalBlocks: sortedBlocks.count,
                            onNext: { advanceBlock(from: index) },
                            onPrevious: { retreatBlock(from: index) }
                        )
                        // Per-block identity. Every block index renders this
                        // same switch branch, so without an explicit id SwiftUI
                        // keeps one BlockEntryPhaseView alive across blocks:
                        // its @State text cache would leak block 1's times into
                        // block 2's cells, onAppear would never rehydrate the
                        // next block's saved records, and the onDisappear flush
                        // would fire once at dismissal against whichever block
                        // was viewed last. The id forces teardown per block —
                        // flush-then-reload runs at every block boundary.
                        .id(sortedBlocks[index].id)
                    }
                case .summary:
                    SessionSummaryPhaseView(
                        session: session,
                        presentAthletes: presentAthletes,
                        isCompleting: isCompleting,
                        onAddBlock: { showingAddBlock = true },
                        onComplete: completeSession,
                        onBack: retreatFromSummary
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        saveAttendance()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button {
                            showingEditSession = true
                        } label: {
                            Label("Edit Session", systemImage: "pencil")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .sheet(isPresented: $showingAddBlock) {
            AddBlockSheet(session: session)
#if os(macOS)
                .frame(minWidth: 480, minHeight: 520)
#endif
        }
        .sheet(isPresented: $showingEditSession) {
            EditSessionSheet(session: session)
#if os(macOS)
                .frame(minWidth: 520, minHeight: 560)
#endif
        }
        .alert("Save Error", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
        .onAppear(perform: setupSession)
    }

    // MARK: - Setup

    /// Hydrates attendance from saved records, defaulting new athletes to present.
    private func setupSession() {
        let existingAttendance: [UUID: AttendanceStatus] = Dictionary(
            uniqueKeysWithValues: (session.attendanceRecords ?? []).compactMap { record in
                guard let athleteID = record.athlete?.id else { return nil }
                return (athleteID, record.status)
            }
        )

        for athlete in sessionAthletes {
            attendanceMap[athlete.id] = existingAttendance[athlete.id] ?? session.defaultAttendanceStatus
        }

        // Sessions created via the new AddSessionSheet have blocks but no
        // PerformanceRecord slots yet (attendance was unknown at create time).
        // Generate any missing slots now that attendance is hydrated.
        backfillSlotsIfNeeded()
    }

    // MARK: - Slot backfill

    /// For each trackable block, reconciles `PerformanceRecord` slots against the
    /// present-athlete list: inserts a missing slot per (present athlete × rep),
    /// and prunes empty slots for athletes no longer present. Also heals slots
    /// stranded beyond the block's rep capacity by old block edits (pruning on
    /// edit shipped in 1.2(4)) or a cross-device merge. Slots that already
    /// hold data (a time, DNS, or DNF) are always kept. Safe to call repeatedly.
    private func backfillSlotsIfNeeded() {
        let presentAthletes = sessionAthletes.filter {
            (attendanceMap[$0.id] ?? session.defaultAttendanceStatus) == .present
        }
        var didChange = false
        for block in sortedBlocks
        where modelContext.reconcileSlots(of: block, presentAthletes: presentAthletes) > 0 {
            didChange = true
        }
        if didChange {
            SyncStore.saveLoggingFailure(modelContext, "Performance slot backfill")
        }
    }

    // MARK: - Navigation

    /// Persist attendance and move to first block or summary if no blocks exist.
    private func advanceFromAttendance() {
        saveAttendance()
        // Re-run backfill in case attendance changed (athletes marked present
        // who weren't before need their slots created).
        backfillSlotsIfNeeded()
        phase = sortedBlocks.isEmpty ? .summary : .blockEntry(0)
    }

    /// Save current block entries and navigate forward.
    private func advanceBlock(from index: Int) {
        do {
            try SyncStore.save(modelContext)
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
        phase = (index + 1 < sortedBlocks.count) ? .blockEntry(index + 1) : .summary
    }

    /// Save current progress and navigate backward.
    private func retreatBlock(from index: Int) {
        do {
            try SyncStore.save(modelContext)
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
        phase = index > 0 ? .blockEntry(index - 1) : .attendance
    }

    /// Navigate back from summary to the previous phase.
    private func retreatFromSummary() {
        phase = sortedBlocks.isEmpty ? .attendance : .blockEntry(sortedBlocks.count - 1)
    }

    // MARK: - Save

    /// Upsert attendance records for all session athletes and persist them.
    /// On a completed/cancelled session, records are only created for athletes
    /// the coach explicitly toggled away from the absent default — untouched
    /// roster newcomers must not gain attendance from a review pass.
    private func saveAttendance() {
        for athlete in sessionAthletes {
            let status = attendanceMap[athlete.id] ?? session.defaultAttendanceStatus
            if let existing = (session.attendanceRecords ?? []).first(where: { $0.athlete?.id == athlete.id }) {
                // Only write a real change: a no-op assignment can still mark the record changed,
                // re-stamping it `now` and pushing this device's stale view over another coach's edit.
                if existing.status != status {
                    existing.status = status
                }
            } else if session.status.isOpen || status != session.defaultAttendanceStatus {
                let record = AttendanceRecord(athlete: athlete, session: session, status: status)
                modelContext.insert(record)
            }
        }
        do {
            try SyncStore.save(modelContext)
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }

    /// Mark the session as completed, save, and dismiss the logger. On a failed save the
    /// status is restored so the session doesn't read as completed while unsaved.
    private func completeSession() {
        isCompleting = true
        Task { @MainActor in
            let previousStatus = session.status
            session.status = .completed
            do {
                try SyncStore.save(modelContext)
                dismiss()
            } catch {
                session.status = previousStatus
                isCompleting = false
                saveErrorMessage = error.localizedDescription
                showSaveError = true
            }
        }
    }
}

/// Displays a horizontal step indicator for the multi-step flow.
struct PhaseStepIndicator: View {
    /// The 1-based index of the current step.
    let currentStep: Int
    /// The total number of steps in the flow.
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...max(totalSteps, 1), id: \.self) { step in
                Capsule()
                    .fill(
                        step < currentStep  ? Color.accentColor.opacity(0.4)  // completed
                      : step == currentStep ? Color.accentColor               // current
                      : Color.secondary.opacity(0.2)                          // remaining
                    )
                    .frame(height: 4)
                    .animation(.spring(response: 0.3), value: currentStep)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 8)
    }
}

// MARK: - Attendance Phase

/// First step of the logger, where the coach records attendance.
struct AttendancePhaseView: View {
    let session: CoachSession
    let athletes: [Athlete]
    @Binding var attendanceMap: [UUID: AttendanceStatus]
    let onDone: () -> Void

    /// The number of athletes currently marked present.
    var presentCount: Int {
        athletes.filter { (attendanceMap[$0.id] ?? session.defaultAttendanceStatus) == .present }.count
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    // `.buttonStyle(.plain)` is load-bearing here, not cosmetic:
                    // without it, two adjacent Buttons in one List row shared a
                    // merged tap target and every tap — regardless of which
                    // button's label was hit — ran the LAST button's action.
                    // Coaches tapping "Mark All Present" were silently marking
                    // the whole roster absent instead. `.foregroundStyle` restores
                    // the accent-color look the default button style provided.
                    Button("Mark All Present") {
                        for athlete in athletes { attendanceMap[athlete.id] = .present }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .comfortableTapTarget()
                    .keyboardShortcut("p", modifiers: [.command, .option])
                    .accessibilityIdentifier("attendance.markAllPresentButton")

                    Button("Mark All Absent") {
                        for athlete in athletes { attendanceMap[athlete.id] = .absent }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .comfortableTapTarget()
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .accessibilityIdentifier("attendance.markAllAbsentButton")

                    Spacer()
                }
            }

            Section {
                ForEach(athletes) { athlete in
                    AttendanceToggleRow(
                        athlete: athlete,
                        status: Binding(
                            get: { attendanceMap[athlete.id] ?? session.defaultAttendanceStatus },
                            set: { attendanceMap[athlete.id] = $0 }
                        )
                    )
                }
            } header: {
                HStack {
                    Text("\(presentCount) of \(athletes.count) present")
                    Spacer()
                }
            } footer: {
                Text("Tap status to cycle: Present → Absent → Excused")
            }
        }
        .navigationTitle("Attendance")
        .safeAreaInset(edge: .top, spacing: 0) {
            PhaseStepIndicator(currentStep: 1, totalSteps: (session.sessionBlocks?.count ?? 0) + 2)
                .background(.bar)
        }
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Next") { onDone() }
                    .fontWeight(.bold)
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
            }
        }
    }
}

/// Row that shows one athlete and allows the status to be cycled quickly.
struct AttendanceToggleRow: View {
    let athlete: Athlete
    @Binding var status: AttendanceStatus

    var body: some View {
        AdaptiveStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(athlete.fullName).font(.body)
                HStack(spacing: 6) {
                    CategoryPill(category: athlete.ageCategory)
                    if let gender = athlete.gender {
                        Text(gender == .male ? "M" : "F")
                            .font(.caption)
                            .foregroundStyle(Color.readableSecondary)
                    }
                }
            }
            AdaptiveSpacer()
            Button { cycleStatus() } label: {
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(status.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(statusColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(statusColor.opacity(0.1))
                .clipShape(Capsule())
                .comfortableTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Attendance for \(athlete.fullName)")
            .accessibilityValue(status.rawValue)
            .accessibilityHint("Changes to the next status")
            .accessibilityInputLabels([status.rawValue, "Attendance for \(athlete.fullName)"])
        }
        .padding(.vertical, 4)
    }

    /// Color used to represent the current `AttendanceStatus`.
    var statusColor: Color {
        switch status {
        case .present: return .readableGreen
        case .absent:  return .readableRed
        case .excused: return .readableOrange
        }
    }

    /// Cycles the `status` through Present → Absent → Excused.
    func cycleStatus() {
        switch status {
        case .present: status = .absent
        case .absent:  status = .excused
        case .excused: status = .present
        }
    }
}

// MARK: - Block Entry Phase

/// Records block results for athletes marked present.
struct BlockEntryPhaseView: View {
    let session: CoachSession
    let block: SessionBlock
    let presentAthletes: [Athlete]
    let blockIndex: Int
    let totalBlocks: Int
    let onNext: () -> Void
    let onPrevious: () -> Void

    @Environment(\.modelContext) private var modelContext
    /// In-memory text cache keyed by athlete ID and repetition number.
    @State private var timeEntries: [UUID: [Int: String]] = [:]
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    /// Drives the rep×athlete focus chain. Set by `advanceFocus(from:)` after
    /// each commit so Return / DNS-chip tap moves the keyboard to the next
    /// empty cell. Reset to nil when the chain runs out so the keyboard dismisses.
    @FocusState private var focusedField: FocusField?
    /// Fully-logged athletes whose collapsed summary row the coach tapped to
    /// re-expand for corrections (sketch D). Resets with the phase view.
    @State private var expandedAthleteOverrides: Set<UUID> = []
    /// Sticky per-device layout for multi-rep time-entry blocks: athlete cards
    /// (default) or the compact rep×athlete grid (sketch B).
    @AppStorage("loggerEntryLayoutGrid") private var useGridLayout = false

    /// True for blocks with no per-athlete data to capture (technique,
    /// weights, circuit, core). These render as a checkpoint screen the
    /// coach taps to acknowledge instead of a per-athlete grid.
    private var isCheckpointBlock: Bool {
        switch block.blockType {
        case .technique, .weights, .circuit, .core:
            return true
        case .paddleDistance, .paddleTimePieces, .paddlePyramid,
             .runDistance, .runIntervals:
            return false
        }
    }

    var body: some View {
        Group {
            if isCheckpointBlock {
                StructuralBlockCheckpoint(block: block, onMarkComplete: onNext)
            } else {
                perAthleteEntryContent
            }
        }
        .navigationTitle("Block \(blockIndex + 1) of \(totalBlocks)")
        .safeAreaInset(edge: .top, spacing: 0) {
            PhaseStepIndicator(currentStep: blockIndex + 2, totalSteps: totalBlocks + 2)
                .background(.bar)
        }
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel(blockIndex == 0 ? "Back to Attendance" : "Back to Block \(blockIndex)")
                .keyboardShortcut(.leftArrow, modifiers: [.command])
            }
            ToolbarItem(placement: .principal) {
                Text(block.blockName)
                    .font(.headline)
                    .lineLimit(1)
            }
            ToolbarItem(placement: .automatic) {
                Button(action: onNext) {
                    HStack(spacing: 4) {
                        Text(blockIndex + 1 == totalBlocks ? "Summary" : "Next")
                            .font(.subheadline)
                        Image(systemName: "chevron.right")
                            .accessibilityHidden(true)
                    }
                    .fontWeight(.semibold)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .accessibilityIdentifier("blockEntry.nextButton")
            }
        }
        .onAppear { loadExistingEntries() }
        .alert("Save Error", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
        .onDisappear {
            // Skip text-entry flush for checkpoint blocks (no entries to save).
            guard !isCheckpointBlock else { return }
            for athlete in presentAthletes {
                guard let reps = timeEntries[athlete.id] else { continue }
                for (rep, str) in reps {
                    saveEntry(athlete: athlete, rep: rep, timeStr: str)
                }
            }
        }
    }

    /// Hydrates the local text cache from pre-generated `PerformanceRecord` slots.
    /// Pending slots initialize the athlete's dict but leave the text empty (shows placeholder).
    private func loadExistingEntries() {
        for record in (block.performanceRecords ?? []) {
            guard let aid = record.athlete?.id else { continue }
            if timeEntries[aid] == nil { timeEntries[aid] = [:] }
            switch record.status {
            case .dns:
                timeEntries[aid]?[record.repNumber] = "DNS"
            case .dnf:
                timeEntries[aid]?[record.repNumber] = "DNF"
            case .complete:
                timeEntries[aid]?[record.repNumber] = record.formattedTime
            case .pending:
                break // Empty text field — no cache entry needed.
            }
        }
    }

    /// Updates the pre-generated `PerformanceRecord` slot for this athlete and rep in-place.
    /// Clearing a field resets the slot to `.pending`; a valid time marks it `.complete`;
    /// DNS/DNF set the status directly. If no slot exists (block added before attendance),
    /// one is created as a defensive fallback.
    private func saveEntry(athlete: Athlete, rep: Int, timeStr: String) {
        let trimmed = timeStr.trimmingCharacters(in: .whitespaces)
        let upper = trimmed.uppercased()
        let isDNS = upper == "DNS"
        let isDNF = upper == "DNF"
        let timeMs = (isDNS || isDNF || trimmed.isEmpty) ? nil : parseTimeToMs(trimmed)
        // A zero time isn't a real result (it would become a permanent all-time PB via `.min()`,
        // and the backend rejects a non-positive COMPLETE time outright) — treat it the same as
        // an unparseable entry rather than silently saving it.
        if !trimmed.isEmpty && !isDNS && !isDNF && (timeMs == nil || timeMs == 0) {
            saveErrorMessage = "Enter a time greater than zero, DNS, DNF, or clear the field."
            showSaveError = true
            return
        }

        if let existing = (block.performanceRecords ?? []).first(where: {
            $0.athlete?.id == athlete.id && $0.repNumber == rep
        }) {
            if trimmed.isEmpty {
                existing.status = .pending
                existing.recordedTimeMs = nil
            } else {
                existing.recordedTimeMs = timeMs
                existing.status = isDNS ? .dns : isDNF ? .dnf : timeMs != nil ? .complete : .pending
            }
        } else if !trimmed.isEmpty && rep <= block.repetitionCount {
            // Defensive fallback: slot was not pre-generated (e.g. block added before attendance).
            // Clamped to the block's current capacity — uncommitted text cached for a rep beyond a
            // since-shrunk block (e.g. typed but not confirmed before Edit Session reduced the rep
            // count) must not resurrect a phantom out-of-capacity record on the next flush.
            let record = PerformanceRecord(
                athlete: athlete,
                sessionBlock: block,
                repNumber: rep,
                recordedTimeMs: timeMs,
                status: isDNS ? .dns : isDNF ? .dnf : timeMs != nil ? .complete : .pending
            )
            modelContext.insert(record)
        }
        do {
            try SyncStore.save(modelContext)
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }
}

// MARK: - Per-Athlete Entry Content

extension BlockEntryPhaseView {
    /// Reps the entry UI renders for this block.
    fileprivate var blockRepCount: Int { max(block.repetitionCount, 1) }

    /// True when the compact rep×athlete grid is both available and selected.
    /// The grid is offered only for multi-rep time-entry blocks — check-off
    /// blocks already render a compact per-set chip grid of their own.
    fileprivate var isGridActive: Bool {
        useGridLayout && block.requiresTimeEntry && blockRepCount > 1
    }

    /// True when the cached text for this cell is a committed-worthy value —
    /// a parseable time or a DNS/DNF marker — so a half-typed invalid time
    /// never reads as "logged".
    private func cellFilled(_ athleteID: UUID, rep: Int) -> Bool {
        isLoggableEntryText(timeEntries[athleteID]?[rep] ?? "")
    }

    /// True when every rep is logged for this athlete: a valid time, DNS, or
    /// DNF per rep in time-entry mode; every slot resolved off pending in
    /// check-off mode.
    private func isFullyLogged(_ athlete: Athlete) -> Bool {
        if block.requiresTimeEntry {
            return (1...blockRepCount).allSatisfy { cellFilled(athlete.id, rep: $0) }
        }
        let resolvedReps = Set((block.performanceRecords ?? [])
            .filter { $0.athlete?.id == athlete.id
                   && $0.repNumber <= blockRepCount
                   && $0.status != .pending }
            .map(\.repNumber))
        return resolvedReps.count == blockRepCount
    }

    /// A fully-logged athlete's card collapses to a summary row (sketch D)
    /// unless the coach re-expanded it — or it currently owns the keyboard,
    /// so a card can never collapse out from under mid-entry typing.
    private func isCollapsed(_ athlete: Athlete) -> Bool {
        isFullyLogged(athlete)
            && !expandedAthleteOverrides.contains(athlete.id)
            && focusedField?.athleteID != athlete.id
    }

    /// The scroll layout for blocks that capture per-athlete per-rep data
    /// (paddle/run distance, time pieces, intervals, pyramid): athlete cards
    /// by default, or the rep×athlete grid when toggled on (sketch B).
    fileprivate var perAthleteEntryContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    BlockHeaderCard(block: block, index: blockIndex, total: totalBlocks)

                    if !presentAthletes.isEmpty && block.requiresTimeEntry && blockRepCount > 1 {
                        layoutTogglePicker
                    }

                    entryListContent
                }
                .padding(16)
            }
            // Follow the focus chain across athletes: when it wraps past the end
            // of one athlete's reps to the next athlete, scroll that card into
            // view so the coach can see the cell that just took the keyboard.
            // Without this, advancing to an off-screen athlete moves focus the
            // coach can't see (and an unrealized LazyVGrid cell may not take it).
            // Intra-athlete rep hops are skipped — that card is already on screen.
            .onChange(of: focusedField) { oldValue, newValue in
                // Card mode only: in grid mode the athlete rows carry no
                // scroll-anchor ids, and the nested horizontal ScrollView
                // makes proxy.scrollTo unreliable (see CLAUDE.md gotcha).
                // Only follow genuine athlete-to-athlete hops in the chain.
                // Require a non-nil oldValue so the initial focus (e.g. the
                // coach tapping a field directly) doesn't yank an already-
                // visible card to center; same-athlete rep hops are skipped too.
                guard !isGridActive,
                      let target = newValue, let old = oldValue,
                      old.athleteID != target.athleteID else { return }
                withAnimation(Motion.animation(.easeInOut(duration: 0.25))) {
                    proxy.scrollTo(target.athleteID, anchor: .center)
                }
            }
        }
    }

    /// The athlete list in the coach's chosen layout: empty-state card, the
    /// rep×athlete grid, or the default per-athlete cards with fully-logged
    /// athletes collapsed to summary rows.
    @ViewBuilder
    private var entryListContent: some View {
        if presentAthletes.isEmpty {
            EmptyCard(message: "No athletes marked present",
                      systemImage: "person.slash")
        } else if isGridActive {
            gridEntryContent
        } else {
            ForEach(presentAthletes) { athlete in
                athleteRow(for: athlete)
            }
        }
    }

    /// One athlete's entry UI in card mode: the full time-entry card, or the
    /// collapsed summary row once every rep is logged (sketch D). Both carry
    /// the athlete id as scroll anchor for the focus-follow.
    ///
    /// The collapse/expand animation is scoped to just this row (`value:
    /// isCollapsed(athlete)`), not the whole athlete list — a blanket
    /// `.animation(value:)` on the enclosing VStack used to animate every
    /// sibling card's layout on any single row's collapse/expand, so the
    /// keyboard's own appearance (requested by the coach's next tap into the
    /// freshly-expanded field) had to wait behind a needlessly large
    /// transaction. Confirmed via 2026-07 keyboard-lag investigation.
    @ViewBuilder
    private func athleteRow(for athlete: Athlete) -> some View {
        Group {
            if isCollapsed(athlete) {
                CollapsedAthleteRow(
                    athlete: athlete,
                    repCount: blockRepCount,
                    onExpand: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            _ = expandedAthleteOverrides.insert(athlete.id)
                        }
                    }
                )
            } else {
                AthleteTimeEntryCard(
                    athlete: athlete,
                    block: block,
                    session: session,
                    entries: Binding(
                        get: { timeEntries[athlete.id] ?? [:] },
                        set: { timeEntries[athlete.id] = $0 }
                    ),
                    focusedField: $focusedField,
                    onCommit: { rep, str in
                        saveEntry(athlete: athlete, rep: rep, timeStr: str)
                        advanceFocus(from: FocusField(athleteID: athlete.id, rep: rep))
                    }
                )
            }
        }
        .id(athlete.id)
        .animation(.easeInOut(duration: 0.2), value: isCollapsed(athlete))
    }

    /// Segmented cards/grid switch shown above the athlete list for multi-rep
    /// time-entry blocks.
    private var layoutTogglePicker: some View {
        HStack {
            Spacer()
            Picker("Layout", selection: $useGridLayout) {
                Image(systemName: "rectangle.grid.1x2")
                    .tag(false)
                    .accessibilityLabel("Athlete cards")
                Image(systemName: "tablecells")
                    .tag(true)
                    .accessibilityLabel("Rep grid")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 110)
        }
    }

    private static let gridNameColumnWidth: CGFloat = 118
    private static let gridCellWidth: CGFloat = 92

    /// Pivot layout (sketch B): one row per athlete, one column per rep, in a
    /// horizontal scroller. Reuses `TimeTextField`, the shared `timeEntries`
    /// cache, and the same save + focus-advance pipeline as the card layout —
    /// athlete-major advance walks across the row, then down.
    private var gridEntryContent: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 10) {
                GridRow {
                    Text("Athlete")
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundStyle(Color.readableSecondary)
                        .frame(width: Self.gridNameColumnWidth, alignment: .leading)
                    ForEach(1...blockRepCount, id: \.self) { rep in
                        Text("Rep \(rep)")
                            .font(.caption2).fontWeight(.semibold)
                            .foregroundStyle(Color.readableSecondary)
                            .frame(width: Self.gridCellWidth)
                    }
                }
                ForEach(presentAthletes) { athlete in
                    GridRow {
                        Text(athlete.fullName)
                            .font(.caption).fontWeight(.medium)
                            .lineLimit(1).truncationMode(.tail)
                            .frame(width: Self.gridNameColumnWidth, alignment: .leading)
                        ForEach(1...blockRepCount, id: \.self) { rep in
                            TimeTextField(
                                placeholder: "MM:SS",
                                accessibilityName: "\(athlete.fullName), rep \(rep) time",
                                text: Binding(
                                    get: { timeEntries[athlete.id]?[rep] ?? "" },
                                    set: { timeEntries[athlete.id, default: [:]][rep] = $0 }
                                ),
                                onCommit: {
                                    saveEntry(athlete: athlete, rep: rep,
                                              timeStr: timeEntries[athlete.id]?[rep] ?? "")
                                    advanceFocus(from: FocusField(athleteID: athlete.id, rep: rep))
                                },
                                focusID: FocusField(athleteID: athlete.id, rep: rep),
                                focusedField: $focusedField
                            )
                            .frame(width: Self.gridCellWidth)
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Athlete-major focus advance: from `current`, scan rep+1..totalReps on
    /// the same athlete, then rep 1..totalReps on each subsequent athlete in
    /// `presentAthletes` order. Lands on the first cell whose `timeEntries`
    /// text is empty (DNS/DNF cells count as filled — they have non-empty
    /// text). When no empty cell remains, sets `focusedField` to nil so the
    /// keyboard dismisses and the coach knows the block is complete.
    fileprivate func advanceFocus(from current: FocusField) {
        let totalReps = max(block.repetitionCount, 1)
        guard let startIdx = presentAthletes.firstIndex(where: { $0.id == current.athleteID }) else {
            focusedField = nil
            return
        }
        var athleteIdx = startIdx
        var startRep = current.rep + 1
        while athleteIdx < presentAthletes.count {
            let candidate = presentAthletes[athleteIdx]
            if startRep <= totalReps {
                for rep in startRep...totalReps {
                    let cellText = (timeEntries[candidate.id]?[rep] ?? "")
                        .trimmingCharacters(in: .whitespaces)
                    if cellText.isEmpty {
                        focusedField = FocusField(athleteID: candidate.id, rep: rep)
                        return
                    }
                }
            }
            athleteIdx += 1
            startRep = 1
        }
        focusedField = nil
    }
}

// MARK: - Structural Block Checkpoint

/// Simple checkpoint screen for blocks with no per-athlete data to capture
/// (warmup, cooldown, technique, weights, circuit, core). Shows the block
/// info read-only and a single "Mark Complete" button that advances the
/// session via the parent's onNext callback.
private struct StructuralBlockCheckpoint: View {
    let block: SessionBlock
    let onMarkComplete: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                infoCard
                Spacer(minLength: 40)
                completeButton
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(typeColor)
                Text(block.blockType.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.readableSecondary)
                Spacer()
                if let dur = block.durationSeconds, dur > 0 {
                    Text(formatDurationLabel(dur))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.readableSecondary)
                }
            }
            Text(block.blockName)
                .font(.title2)
                .fontWeight(.bold)
            if let drill = block.drillName, !drill.isEmpty {
                Label(drill, systemImage: "figure.run")
                    .font(.subheadline)
            }
            if let note = block.coachNote, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(Color.readableSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var completeButton: some View {
        Button(action: onMarkComplete) {
            Label("Mark Complete", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.filledGreen, in: RoundedRectangle(cornerRadius: 14))
        }
        .keyboardShortcut(.return, modifiers: [.command])
    }

    private var iconName: String {
        switch block.blockType {
        case .technique: return "scope"
        case .weights:   return "dumbbell.fill"
        case .circuit:   return "arrow.triangle.2.circlepath"
        case .core:      return "figure.core.training"
        default:         return "questionmark.circle"
        }
    }

    private var typeColor: Color {
        switch block.blockType {
        case .technique:      return .purple
        case .weights, .core: return .readableOrange
        case .circuit:        return .readableRed
        default:              return .secondary
        }
    }
}

// MARK: - Block Header Card

/// Summary header for a block showing name, type, reps, target distance, and zone.
struct BlockHeaderCard: View {
    @Bindable var block: SessionBlock
    let index: Int
    let total: Int
    @Environment(\.modelContext) private var modelContext

    /// Computes km from reps × metres when `distanceKm` is nil.
    var autoKm: Double? {
        guard let dist = block.targetDistanceMetres else { return nil }
        return Double(block.repetitionCount) * dist / 1000.0
    }

    /// SF Symbol beside block distance. Paddle blocks use outdoor rowing (no kayak
    /// glyph in SF Symbols); run blocks use the runner figure.
    private var distanceIconName: String {
        switch block.blockType {
        case .paddleDistance, .paddleTimePieces, .paddlePyramid:
            return "figure.outdoor.rowing"
        case .runDistance, .runIntervals:
            return "figure.run"
        default:
            return "water.waves"
        }
    }

    /// Formats a rest interval in seconds as "Xm Ys rest", omitting the
    /// minutes or seconds component when it is zero.
    func restLabel(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        switch (m, s) {
        case (0, _): return "\(s)s rest"
        case (_, 0): return "\(m)m rest"
        default:     return "\(m)m \(s)s rest"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(block.blockName)
                        .font(.headline)
                    HStack(spacing: 8) {
                        Text(block.blockType.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                        if block.repetitionCount > 1 {
                            Text("×\(block.repetitionCount)")
                                .font(.caption)
                                .foregroundStyle(Color.readableSecondary)
                        }
                        if let dist = block.targetDistanceMetres {
                            // Plain String so Text can't apply locale number
                            // grouping ("1,000m") to the distance.
                            let distanceLabel = dist >= 1000 ? "\(Int(dist / 1000)) km" : "\(Int(dist)) m"
                            Text(distanceLabel)
                                .font(.caption)
                                .foregroundStyle(Color.readableSecondary)
                        }
                    }
                }
                Spacer()

                if let zone = block.trainingZone {
                    Text(zone.rawValue)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(zone.color.opacity(0.15))
                        .foregroundStyle(zone.color)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 16) {
                if let km = block.distanceKm ?? autoKm {
                    HStack(spacing: 4) {
                        Image(systemName: distanceIconName)
                            .font(.caption)
                            .foregroundStyle(Color.readableSecondary)
                        Text(String(format: "%.2f km", km))
                            .font(.caption)
                            .foregroundStyle(block.trainingZone == .recovery ? .secondary : .primary)
                        if block.trainingZone == .recovery {
                            Text("(not counted)")
                                .font(.caption2)
                                .foregroundStyle(Color.readableSecondary)
                        }
                    }
                }
                if let rest = block.restIntervalSeconds, rest > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.caption)
                            .foregroundStyle(Color.readableSecondary)
                        Text(restLabel(rest))
                            .font(.caption)
                            .foregroundStyle(Color.readableSecondary)
                    }
                }
                Spacer()
                if let zone = block.trainingZone {
                    Text(zone.description)
                        .font(.caption2)
                        .foregroundStyle(Color.readableSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Collapsed Athlete Row

/// Summary row shown in place of a fully-logged athlete's entry card
/// (sketch D), so the visible list shrinks to "what's left". Tap re-expands
/// the full card for corrections.
private struct CollapsedAthleteRow: View {
    let athlete: Athlete
    let repCount: Int
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            AdaptiveStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.readableGreen)
                // Wraps rather than truncating ("Jorda…") at large text sizes; the name is the row.
                Text(athlete.fullName)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                AdaptiveSpacer()
                Text(repCount == 1 ? "1 rep ✓" : "\(repCount) reps ✓")
                    .font(.caption)
                    .foregroundStyle(Color.readableGreen)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Color.readableSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(athlete.fullName), all \(repCount) reps logged")
        .accessibilityHint("Expands the entry card for corrections")
    }
}

// MARK: - Athlete Time Entry Card

/// Card for entering one or more times for a single athlete in the current block.
struct AthleteTimeEntryCard: View {
    let athlete: Athlete
    let block: SessionBlock
    let session: CoachSession
    @Binding var entries: [Int: String]
    @FocusState.Binding var focusedField: FocusField?
    let onCommit: (Int, String) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var showingNoteSheet = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    private var noteAccessibilityName: String {
        hasNote ? "Edit note for \(athlete.fullName)" : "Add note for \(athlete.fullName)"
    }

    /// True when a session-level note already exists for this athlete.
    private var hasNote: Bool {
        (session.athleteNotes ?? []).contains { $0.athlete?.id == athlete.id }
    }

    /// Best time this athlete has ever recorded in any block with the same name.
    private var pbMs: Int? {
        (athlete.performanceRecords ?? [])
            .filter { $0.sessionBlock?.blockName == block.blockName && $0.status == .complete }
            .compactMap(\.recordedTimeMs)
            .min()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AdaptiveStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Text(athlete.firstName.prefix(1) + athlete.lastName.prefix(1))
                            .font(.caption).fontWeight(.bold).foregroundStyle(Color.accentColor)
                            // The circle is a fixed 34pt; past xxLarge the initials became "…".
                            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                            .accessibilityHidden(true)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(athlete.fullName)
                        .font(.subheadline).fontWeight(.medium)
                    if let gender = athlete.gender {
                        Text(gender == .male ? "M" : "F")
                            .font(.caption2)
                            .foregroundStyle(Color.readableSecondary)
                    }
                }
                AdaptiveSpacer()
                if let pb = pbMs {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("PB")
                            .font(.caption2)
                            .foregroundStyle(Color.readableSecondary)
                        Text(formatMillisecondsForDisplay(pb))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.readableGreen)
                    }
                }
                CategoryPill(category: athlete.ageCategory)
                Button {
                    showingNoteSheet = true
                } label: {
                    Image(systemName: hasNote ? "note.text" : "note.text.badge.plus")
                        .foregroundStyle(hasNote ? Color.readableBlue : .secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(noteAccessibilityName)
                .accessibilityInputLabels(["Note", noteAccessibilityName])
            }

            if !block.requiresTimeEntry {
                checkOffContent
            } else if block.repetitionCount == 1 {
                HStack(spacing: 8) {
                    TimeTextField(
                        placeholder: "MM:SS.ms",   // DNS / DNF have their own chips right beside the field
                        accessibilityName: "\(athlete.fullName), time",
                        text: Binding(
                            get: { entries[1] ?? "" },
                            set: { entries[1] = $0 }
                        ),
                        onCommit: { onCommit(1, entries[1] ?? "") },
                        focusID: FocusField(athleteID: athlete.id, rep: 1),
                        focusedField: $focusedField
                    )
                    quickStatusChip("DNS", for: 1)
                    quickStatusChip("DNF", for: 1)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 8) {
                    ForEach(1...block.repetitionCount, id: \.self) { rep in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Rep \(rep)")
                                .font(.caption2)
                                .foregroundStyle(Color.readableSecondary)
                            TimeTextField(
                                placeholder: "MM:SS",
                                accessibilityName: "\(athlete.fullName), rep \(rep) time",
                                text: Binding(
                                    get: { entries[rep] ?? "" },
                                    set: { entries[rep] = $0 }
                                ),
                                onCommit: { onCommit(rep, entries[rep] ?? "") },
                                focusID: FocusField(athleteID: athlete.id, rep: rep),
                                focusedField: $focusedField
                            )
                            HStack(spacing: 4) {
                                quickStatusChip("DNS", for: rep)
                                quickStatusChip("DNF", for: rep)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showingNoteSheet) {
            AthleteNoteSheet(athlete: athlete, session: session, modelContext: modelContext)
        }
        .alert("Save Error", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
    }

    /// Compact orange pill used to mark a rep as DNS or DNF in one tap. Tap
    /// fills the cell's text with the label and re-fires `onCommit` so the
    /// parent's save + focus-advance pipeline runs exactly as if the coach
    /// had typed the value and pressed Return.
    @ViewBuilder
    private func quickStatusChip(_ label: String, for rep: Int) -> some View {
        Button {
            entries[rep] = label
            onCommit(rep, label)
        } label: {
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.readableOrange)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Mark rep \(rep) as \(label == "DNS" ? "Did Not Start" : "Did Not Finish")"
        )
    }

    // MARK: - Check-off mode

    /// Renders per-rep checkboxes when the block is in check-off mode
    /// (requiresTimeEntry == false). Pyramids are grouped visually by set.
    @ViewBuilder
    private var checkOffContent: some View {
        if let pattern = block.prescribedRepDurationsSec, !pattern.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<max(block.setCount, 1), id: \.self) { setIndex in
                    VStack(alignment: .leading, spacing: 4) {
                        if block.setCount > 1 {
                            Text("Set \(setIndex + 1)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.readableSecondary)
                        }
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 56, maximum: 72), spacing: 6)],
                            alignment: .leading,
                            spacing: 6
                        ) {
                            ForEach(pattern.indices, id: \.self) { repIdxInSet in
                                let globalRep = setIndex * pattern.count + repIdxInSet + 1
                                RepCheckbox(
                                    rep: globalRep,
                                    prescribedLabel: formatChipDuration(pattern[repIdxInSet]),
                                    status: statusFor(rep: globalRep),
                                    onToggle: { toggleStatus(rep: globalRep) },
                                    onSetStatus: { setStatus(rep: globalRep, status: $0) }
                                )
                            }
                        }
                    }
                }
            }
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 56, maximum: 72), spacing: 6)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(1...max(block.repetitionCount, 1), id: \.self) { rep in
                    RepCheckbox(
                        rep: rep,
                        prescribedLabel: nil,
                        status: statusFor(rep: rep),
                        onToggle: { toggleStatus(rep: rep) },
                        onSetStatus: { setStatus(rep: rep, status: $0) }
                    )
                }
            }
        }
    }

    private func statusFor(rep: Int) -> RepEntryStatus {
        (block.performanceRecords ?? [])
            .first { $0.athlete?.id == athlete.id && $0.repNumber == rep }?
            .status ?? .pending
    }

    private func toggleStatus(rep: Int) {
        let current = statusFor(rep: rep)
        setStatus(rep: rep, status: current == .complete ? .pending : .complete)
    }

    private func setStatus(rep: Int, status: RepEntryStatus) {
        // Undo only this rep's change on a failed save; a context-wide rollback could
        // discard other unsaved logger edits.
        let undo: () -> Void
        if let record = (block.performanceRecords ?? []).first(where: {
            $0.athlete?.id == athlete.id && $0.repNumber == rep
        }) {
            let (oldStatus, oldTimeMs) = (record.status, record.recordedTimeMs)
            undo = { record.status = oldStatus; record.recordedTimeMs = oldTimeMs }
            record.status = status
            record.recordedTimeMs = nil
        } else {
            // Defensive: backfill should have covered this, but create on-demand
            // in case a coach manually marks reps before backfill ran.
            let slot = PerformanceRecord(
                athlete: athlete,
                sessionBlock: block,
                repNumber: rep,
                status: status
            )
            modelContext.insert(slot)
            undo = { modelContext.delete(slot) }
        }
        do {
            try SyncStore.save(modelContext)
        } catch {
            undo()
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }
}

// MARK: - Rep Checkbox

/// One rep cell in check-off mode. Tap toggles between pending and complete.
/// Long-press opens a context menu with Pending / Complete / DNS / DNF.
private struct RepCheckbox: View {
    let rep: Int
    let prescribedLabel: String?
    let status: RepEntryStatus
    let onToggle: () -> Void
    let onSetStatus: (RepEntryStatus) -> Void

    /// 44pt at default text size, scaled with Dynamic Type so the checkmark/DNS/DNF content
    /// (which itself scales via `.title3`/`.caption`) never clips against a fixed-size frame.
    @ScaledMetric(relativeTo: .title3) private var checkboxSize: CGFloat = 44

    var body: some View {
        VStack(spacing: 4) {
            if let label = prescribedLabel {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Color.readableSecondary)
            }
            Button(action: onToggle) {
                statusContent
                    .frame(width: checkboxSize, height: checkboxSize)
                    .background(background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(borderColor, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rep \(rep)")
            .accessibilityValue(status.rawValue)
            .contextMenu {
                Button {
                    onSetStatus(.complete)
                } label: { Label("Mark Complete", systemImage: "checkmark.circle") }
                Button {
                    onSetStatus(.pending)
                } label: { Label("Mark Pending", systemImage: "circle") }
                Divider()
                Button {
                    onSetStatus(.dns)
                } label: { Label("DNS", systemImage: "xmark.circle") }
                Button {
                    onSetStatus(.dnf)
                } label: { Label("DNF", systemImage: "exclamationmark.triangle") }
            }
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch status {
        case .complete:
            Image(systemName: "checkmark")
                .font(.title3.bold())
                .foregroundStyle(.white)
        case .dns:
            Text("DNS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        case .dnf:
            Text("DNF")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        case .pending:
            Text("\(rep)")
                .font(.subheadline)
                .foregroundStyle(Color.readableSecondary)
        }
    }

    private var background: Color {
        switch status {
        case .complete: return .filledGreen
        case .dns:      return .filledRed
        case .dnf:      return .filledOrange
        case .pending:  return .clear
        }
    }

    private var borderColor: Color {
        switch status {
        case .complete, .dns, .dnf: return .clear
        case .pending:              return .gray.opacity(0.4)
        }
    }
}

// MARK: - Athlete Note Sheet

/// Sheet for creating, editing, or deleting a session-scoped note for one athlete.
private struct AthleteNoteSheet: View {
    let athlete: Athlete
    let session: CoachSession
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    private var existingNote: AthleteNote? {
        (session.athleteNotes ?? []).first { $0.athlete?.id == athlete.id }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(athlete.fullName)
                    .font(.headline)
                    .padding(.horizontal)

                TextEditor(text: $text)
                    .font(.body)
                    .padding(10)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .frame(minHeight: 120)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Athlete Note")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                                  existingNote == nil)
                }
                if existingNote != nil {
#if os(iOS)
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) { deleteNote() } label: {
                            Label("Delete Note", systemImage: "trash")
                        }
                    }
#else
                    ToolbarItem(placement: .destructiveAction) {
                        Button(role: .destructive) { deleteNote() } label: {
                            Label("Delete Note", systemImage: "trash")
                        }
                    }
#endif
                }
            }
            .onAppear {
                text = existingNote?.noteText ?? ""
            }
            .alert("Save Error", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { dismiss(); return }
        if let note = existingNote {
            note.noteText = trimmed
        } else {
            let note = AthleteNote(noteText: trimmed, athlete: athlete, session: session)
            note.createdByCoachName = CoachIdentity.currentName(in: modelContext)
            modelContext.insert(note)
        }
        do {
            try SyncStore.save(modelContext)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }

    private func deleteNote() {
        guard let note = existingNote else { dismiss(); return }
        modelContext.delete(note)
        do {
            try SyncStore.save(modelContext)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }
}

// MARK: - Time Text Field

/// Identifies a single cell in the per-athlete × rep time-entry grid so the
/// parent `BlockEntryPhaseView` can drive a focus chain (athlete-major: Return
/// advances to the next empty rep for the same athlete, wrapping to the next
/// athlete when the current one is full). DNS/DNF count as filled and are
/// skipped by the chain.
struct FocusField: Hashable {
    let athleteID: UUID
    let rep: Int
}

/// True when the trimmed text is a loggable rep value: a parseable time above
/// zero (matching `saveEntry`) or a DNS/DNF marker. Single rule shared by `TimeTextField` validation and the
/// logger's fully-logged checks so the two can't drift.
func isLoggableEntryText(_ text: String) -> Bool {
    let t = text.trimmingCharacters(in: .whitespaces).uppercased()
    guard !t.isEmpty else { return false }
    return t == "DNS" || t == "DNF" || (parseTimeToMs(t) ?? 0) > 0
}

/// Text field for timing input that also supports `DNS` and `DNF`.
///
/// Focus is owned by the parent: declare `@FocusState private var focusedField: FocusField?`
/// in the parent, pass `$focusedField` here, and the cell whose `focusID`
/// equals the parent's value is the focused one. Setting the parent's state
/// to another `FocusField` moves focus; setting it to nil dismisses the keyboard.
struct TimeTextField: View {
    let placeholder: String
    /// Spoken name, e.g. "Jordan Rivers, rep 2 time". The placeholder is the same on every field.
    let accessibilityName: String
    @Binding var text: String
    let onCommit: () -> Void
    let focusID: FocusField
    @FocusState.Binding var focusedField: FocusField?

    private var isFocused: Bool { focusedField == focusID }

    /// True if the field is empty, DNS, DNF, or parses to a valid time.
    var isValid: Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty || isLoggableEntryText(text)
    }

    /// Background color indicating validity and focus state.
    var fieldBackground: Color {
        let t = text.trimmingCharacters(in: .whitespaces).uppercased()
        if t.isEmpty { return Color.gray.opacity(0.05) }
        if t == "DNS" || t == "DNF" { return .orange.opacity(0.1) }
        if isFocused { return Color.gray.opacity(0.05) }
        return isValid ? .green.opacity(0.1) : .red.opacity(0.08)
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .accessibilityLabel(accessibilityName)
            .font(.system(.body, design: .monospaced))
            #if os(iOS)
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.center)
            #else
            .multilineTextAlignment(.center)
            #endif
            .focused($focusedField, equals: focusID)
            // Shared identifier — every instance reports the same value.
            // Fine for the current UI test (exactly one athlete × one rep
            // ever on screen at once); would need a per-cell id if a test
            // ever needs to disambiguate between multiple rendered cells.
            .accessibilityIdentifier("block.repField")
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isFocused || isValid ? Color.gray.opacity(0.25) : Color.red.opacity(0.5),
                            lineWidth: 1)
            )
            .contextMenu {
                Button("DNS") { text = "DNS"; onCommit() }
                Button("DNF") { text = "DNF"; onCommit() }
            }
            .onSubmit { onCommit() }
    }
}

// MARK: - Session Summary Phase

/// Final review step before marking the session complete.
struct SessionSummaryPhaseView: View {
    @Bindable var session: CoachSession
    let presentAthletes: [Athlete]
    let isCompleting: Bool
    let onAddBlock: () -> Void
    let onComplete: () -> Void
    let onBack: () -> Void

    /// Blocks sorted for display order.
    var sortedBlocks: [SessionBlock] {
        (session.sessionBlocks ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Count of athletes marked present.
    var totalPresent: Int  { (session.attendanceRecords ?? []).filter { $0.status == .present }.count }
    /// Count of athletes marked absent.
    var totalAbsent: Int   { (session.attendanceRecords ?? []).filter { $0.status == .absent }.count }
    /// Count of athletes marked excused.
    var totalExcused: Int  { (session.attendanceRecords ?? []).filter { $0.status == .excused }.count }
    /// Total number of attendance records.
    var totalAthletes: Int { session.attendanceRecords?.count ?? 0 }

    /// Total km across non-recovery blocks.
    var sessionKm: Double {
        sortedBlocks
            .filter { $0.trainingZone != .recovery }
            .compactMap { $0.effectiveDistanceKm }
            .reduce(0, +)
    }

    /// Headline numbers for the attendance card; Excused and km appear only when non-zero.
    private var attendanceStats: [StatStripItem] {
        var items = [StatStripItem(value: "\(totalPresent)", label: "Present", color: .readableGreen),
                     StatStripItem(value: "\(totalAbsent)", label: "Absent", color: .readableRed)]
        if totalExcused > 0 {
            items.append(StatStripItem(value: "\(totalExcused)", label: "Excused", color: .readableOrange))
        }
        items.append(StatStripItem(value: "\(totalAthletes)", label: "Total", color: .accentColor))
        if sessionKm > 0 {
            items.append(StatStripItem(value: String(format: "%.1f", sessionKm), label: "km", color: .readableOrange))
        }
        return items
    }

    /// km per zone (excluding recovery), omitting zones with zero km.
    var sessionZoneBreakdown: [(zone: TrainingZone, km: Double)] {
        let nonRecoveryBlocks = sortedBlocks.filter { $0.trainingZone != .recovery }
        let zones: [TrainingZone] = [.ga1, .ga2, .e1, .e2, .anMix, .alactic]
        return zones.compactMap { zone in
            let km = nonRecoveryBlocks
                .filter { $0.trainingZone == zone }
                .compactMap { $0.effectiveDistanceKm }
                .reduce(0, +)
            return km > 0 ? (zone, km) : nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                VStack(alignment: .leading, spacing: 6) {
                    Text(session.sessionName)
                        .font(.title2).fontWeight(.bold)
                    if let team = session.team {
                        Text(team.teamName).foregroundStyle(Color.readableSecondary)
                    }
                    if let cue = session.mfCue {
                        HStack(spacing: 6) {
                            Text("MF Cue")
                                .font(.caption)
                                .foregroundStyle(Color.readableSecondary)
                            Text(cue)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }

                    LoggedByLabel(coachName: session.createdByCoachName)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("Attendance", systemImage: "person.2.fill")
                        .labelStyle(AdaptiveLabelStyle())
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(Color.readableSecondary)
                    StatStrip(items: attendanceStats)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 8) {
                    Label("Practice Notes", systemImage: "note.text")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(Color.readableSecondary)
                    TextField("General observations…", text: Binding(
                        get: { session.sessionNote ?? "" },
                        set: { session.sessionNote = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(3...8)
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 12) {
                    AdaptiveStack {
                        Label("Workout Blocks", systemImage: "stopwatch.fill")
                            .labelStyle(AdaptiveLabelStyle())
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(Color.readableSecondary)
                        AdaptiveSpacer()
                        Button { onAddBlock() } label: {
                            Label("Add Block", systemImage: "plus")
                                .font(.caption).fontWeight(.semibold)
                                .comfortableTapTarget()
                        }
                    }

                    if sortedBlocks.isEmpty {
                        Text("No blocks — tap Add Block to log workout data")
                            .font(.subheadline).foregroundStyle(Color.readableSecondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(sortedBlocks) { block in
                                BlockSummaryRow(block: block,
                                               presentCount: presentAthletes.count)
                            }
                        }
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

                if !sessionZoneBreakdown.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Zone Distribution", systemImage: "chart.bar.fill")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(Color.readableSecondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(sessionZoneBreakdown, id: \.zone) { item in
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
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }

                Button(action: onComplete) {
                    Group {
                        if isCompleting {
                            HStack(spacing: 8) {
                                ProgressView().tint(.white)
                                Text("Saving…")
                            }
                        } else {
                            Label("Complete Practice", systemImage: "checkmark.circle.fill")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(isCompleting ? Color.filledGreen.opacity(0.7) : Color.filledGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isCompleting)
                .padding(.top, 4)
                .keyboardShortcut(.return, modifiers: [.command])
                .accessibilityIdentifier("session.completeButton")
            }
            .padding(16)
        }
        .navigationTitle("Summary")
        .safeAreaInset(edge: .top, spacing: 0) {
            let total = sortedBlocks.count + 2
            PhaseStepIndicator(currentStep: total, totalSteps: total)
                .background(.bar)
        }
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .accessibilityHidden(true)
                        Text("Back")
                    }
                }
            }
        }
    }
}

/// Displays a compact summary of a block with zone and progress indicators.
struct BlockSummaryRow: View {
    let block: SessionBlock
    let presentCount: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Side by side normally; stacked at accessibility text sizes, where one row
    /// broke "Paddle Distance" and "recorded" apart mid-word.
    private var rowLayout: AnyLayout { adaptiveLayout(spacing: 8) }
    private var detailsLayout: AnyLayout { adaptiveLayout(spacing: 6) }

    private func adaptiveLayout(spacing: CGFloat) -> AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
    }

    /// Number of unique athletes with at least one filled slot (a time, DNS, or DNF) in this block.
    /// Pending slots are pre-created for every present athlete, so they don't count.
    var recordedCount: Int {
        Set((block.performanceRecords ?? []).filter(\.holdsRecordedData).compactMap { $0.athlete?.id }).count
    }

    /// Distance shown for the block; recovery exclusion is handled by the parent summary.
    var blockKm: Double? {
        block.effectiveDistanceKm
    }

    var body: some View {
        rowLayout {
            VStack(alignment: .leading, spacing: 3) {
                Text(block.blockName).font(.subheadline)
                detailsLayout {
                    Text(block.blockType.rawValue).font(.caption).foregroundStyle(Color.readableSecondary)
                    if let zone = block.trainingZone {
                        Text(zone.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(zone.color.opacity(0.12))
                            .foregroundStyle(zone.color)
                            .clipShape(Capsule())
                    }
                    if let km = blockKm, block.trainingZone != .recovery {
                        Text(String(format: "%.2f km", km))
                            .font(.caption2)
                            .foregroundStyle(Color.readableSecondary)
                    }
                }
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            Text("\(recordedCount)/\(presentCount) recorded")
                .font(.caption)
                .foregroundStyle(recordedCount == presentCount ? Color.readableGreen : Color.readableOrange)
        }
        .padding(.vertical, 4)
    }
}
