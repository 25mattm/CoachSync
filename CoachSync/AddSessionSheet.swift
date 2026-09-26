/// Sheet for creating a new practice with structured blocks.
///
/// Uses pre-insert pattern: a draft `CoachSession` is inserted into the
/// modelContext on appear (with no initial blocks) and deleted on dismiss
/// unless explicitly saved. This lets `AddBlockSheet` operate on a real
/// session for the lifetime of the form. The coach builds the block list
/// from scratch each time — warmup and cooldown are assumed parts of
/// every practice and not tracked as blocks (per coach decision May 2026).

import SwiftUI
import SwiftData

struct AddSessionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var preselectedDate: Date = Date()

    /// The session being constructed. Nil until `onAppear` creates the draft.
    @State private var draftSession: CoachSession?
    /// Set to true once the user explicitly hits Save (or Save & New).
    /// Controls whether `onDisappear` should clean up the draft.
    @State private var hasBeenSaved = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    /// Used to sweep blank-named draft sessions left by an aborted create flow.
    @Query private var allSessions: [CoachSession]

    init(preselectedDate: Date = Date()) {
        self.preselectedDate = preselectedDate
    }

    var body: some View {
        NavigationStack {
            Group {
                if let session = draftSession {
                    DraftSessionForm(
                        session: session,
                        isValid: validateSession(session),
                        onSave: { performSave(session, andNew: false) },
                        onSaveAndNew: { performSave(session, andNew: true) },
                        onCancel: { dismiss() }
                    )
                } else {
                    ProgressView()
                }
            }
            .alert("Couldn't Save Practice", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        }
        .onAppear {
            if draftSession == nil {
                sweepLeakedDrafts()
                draftSession = createDraft(date: preselectedDate)
            }
        }
        .onDisappear { cleanupIfNeeded() }
    }

    // MARK: - Lifecycle

    /// Creates a fresh draft session. Blocks are added by the coach via the
    /// "+ Add Block" affordance — warmup and cooldown are assumed parts of
    /// every practice and not tracked as blocks (per coach decision May 2026).
    private func createDraft(date: Date) -> CoachSession {
        let session = CoachSession(sessionName: "", scheduledDate: date)
        let cal = Calendar.current
        session.startTime = cal.date(bySettingHour: 6, minute: 0, second: 0, of: date) ?? date
        session.endTime = cal.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date
        session.createdByCoachName = CoachIdentity.currentName(in: modelContext)
        modelContext.insert(session)
        Self.registerPendingDraft(session.id)
        return session
    }

    // MARK: - Pending-draft registry (device-local)

    /// UserDefaults key holding the ids of draft sessions THIS DEVICE created
    /// that have not been saved or cleaned up yet. Scoping the sweep to these
    /// ids means a device only ever deletes its own leaked drafts — another
    /// device's in-flight draft that synced in can never be swept from here.
    private static let pendingDraftIDsKey = "CoachSync.pendingDraftSessionIDs"

    private static func pendingDraftIDs() -> [String] {
        UserDefaults.standard.stringArray(forKey: pendingDraftIDsKey) ?? []
    }

    private static func registerPendingDraft(_ id: UUID) {
        var ids = pendingDraftIDs()
        ids.append(id.uuidString)
        UserDefaults.standard.set(ids, forKey: pendingDraftIDsKey)
    }

    private static func unregisterPendingDraft(_ id: UUID) {
        let ids = pendingDraftIDs().filter { $0 != id.uuidString }
        UserDefaults.standard.set(ids, forKey: pendingDraftIDsKey)
    }

    /// Removes draft sessions THIS DEVICE leaked — the app being killed
    /// mid-create (so `.onDisappear` cleanup never fired), or a
    /// `SyncStore.save` triggered by adding a block before the coach
    /// saved. Candidates come exclusively from the device-local pending-draft
    /// registry, so another device's in-flight draft that synced in can never
    /// be swept here. Runs before the new draft is created and registered, so
    /// the fresh draft is never a candidate.
    ///
    /// Belt-and-braces guards on top of registry membership, in case an id
    /// ever lingers after a successful save: blank name only (saved sessions
    /// are always auto-named), never completed, never with attendance, and a
    /// 10-minute grace window (protects a second still-open create window on
    /// this device, e.g. multiple Mac windows).
    private func sweepLeakedDrafts() {
        let pendingIDs = Set(Self.pendingDraftIDs())
        guard !pendingIDs.isEmpty else { return }

        let cutoff = Date().addingTimeInterval(-600)
        let leaked = allSessions.filter {
            pendingIDs.contains($0.id.uuidString) &&
            $0.sessionName.trimmingCharacters(in: .whitespaces).isEmpty &&
            !$0.isArchived &&
            $0.isDeletable &&
            ($0.attendanceRecords?.isEmpty ?? true) &&
            $0.createdAt < cutoff
        }
        for session in leaked {
            modelContext.deleteSessionCascade(session)
            Self.unregisterPendingDraft(session.id)
        }
        if !leaked.isEmpty {
            try? SyncStore.save(modelContext)
        }

        // Prune registry entries whose session no longer exists (deleted on
        // another device or already swept) so the list can't grow unbounded.
        let existingIDs = Set(allSessions.map { $0.id.uuidString })
        for stale in pendingIDs.subtracting(existingIDs) {
            if let uuid = UUID(uuidString: stale) {
                Self.unregisterPendingDraft(uuid)
            }
        }
    }

    /// Deletes the draft session and any attached blocks/records if the form
    /// was dismissed without saving. Uses the cascade helper because the
    /// schema's nullify rules don't auto-clean child records.
    private func cleanupIfNeeded() {
        guard !hasBeenSaved, let session = draftSession else { return }
        Self.unregisterPendingDraft(session.id)
        modelContext.deleteSessionCascade(session)
        try? SyncStore.save(modelContext)
    }

    // MARK: - Save

    private func validateSession(_ session: CoachSession) -> Bool {
        guard let start = session.startTime, let end = session.endTime else { return false }
        return end > start
    }

    /// Persists the current draft. If `andNew` is true, immediately creates a
    /// fresh draft on the same date with team cleared and default blocks.
    private func performSave(_ session: CoachSession, andNew: Bool) {
        // Auto-fill the name if the coach left it blank.
        let trimmed = session.sessionName.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            session.sessionName = autoSessionName(for: session)
        }

        do {
            try SyncStore.save(modelContext)
            hasBeenSaved = true
            Self.unregisterPendingDraft(session.id)

            if andNew {
                // Carry the date forward; clear the team selection (per coach Q1
                // — common pattern is filling multiple teams' sessions for the
                // same day in succession).
                let nextDate = session.scheduledDate
                draftSession = createDraft(date: nextDate)
                hasBeenSaved = false
            } else {
                dismiss()
            }
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }

}

/// Generates a default session name like "U16 Boys · Aug 12" or
/// "Practice · Aug 12". Applied whenever a session would otherwise persist
/// with a blank name — by `performSave` here and by `EditSessionSheet`'s
/// Done — because a blank name is what marks a session as a leaked draft
/// for `sweepLeakedDrafts`.
func autoSessionName(for session: CoachSession) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    let dateStr = formatter.string(from: session.scheduledDate)
    if let team = session.team {
        return "\(team.teamName) · \(dateStr)"
    }
    return "Practice · \(dateStr)"
}

// MARK: - DraftSessionForm

/// The actual form bound to a draft session. Extracted so `@Bindable` gives us
/// SwiftUI observation of the underlying `@Model`.
private struct DraftSessionForm: View {
    @Bindable var session: CoachSession
    let isValid: Bool
    let onSave: () -> Void
    let onSaveAndNew: () -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Team.teamName) private var teams: [Team]

    @State private var showingAddBlock = false
    @State private var blockToEdit: SessionBlock? = nil

    private var sortedBlocks: [SessionBlock] {
        (session.sessionBlocks ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        Form {
            practiceInfoSection
            blocksSection
        }
        .navigationTitle("New Practice")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
                    .accessibilityIdentifier("session.cancelButton")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: onSave)
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                    .accessibilityIdentifier("session.saveButton")
            }
            ToolbarItem(placement: .confirmationAction) {
                Menu {
                    Button("Save & New", action: onSaveAndNew)
                        .disabled(!isValid)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("More save options")
                }
            }
        }
        .sheet(isPresented: $showingAddBlock) {
            AddBlockSheet(session: session)
#if os(macOS)
                .frame(minWidth: 480, minHeight: 520)
#endif
        }
        .sheet(item: $blockToEdit) { block in
            AddBlockSheet(session: session, existingBlock: block)
#if os(macOS)
                .frame(minWidth: 480, minHeight: 520)
#endif
        }
        .onChange(of: session.scheduledDate) { _, newDate in
            if let start = session.startTime {
                session.startTime = combine(date: newDate, with: start)
            }
            if let end = session.endTime {
                session.endTime = combine(date: newDate, with: end)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var practiceInfoSection: some View {
        Section("Practice Info") {
            Picker("Team", selection: $session.team) {
                Text("All Athletes").tag(nil as Team?)
                ForEach(teams) { team in
                    Text(team.teamName).tag(team as Team?)
                }
            }

            DatePicker("Date", selection: $session.scheduledDate,
                       displayedComponents: .date)

            DatePicker("Start", selection: Binding(
                get: { session.startTime ?? session.scheduledDate },
                set: { session.startTime = $0 }
            ), displayedComponents: .hourAndMinute)

            DatePicker("End", selection: Binding(
                get: { session.endTime ?? session.scheduledDate },
                set: { session.endTime = $0 }
            ), displayedComponents: .hourAndMinute)

            if !isValid {
                Text("End time must be after start time")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            TextField("Name (auto-fills if blank)", text: $session.sessionName)

            TextField("MF Cue (optional)", text: Binding(
                get: { session.mfCue ?? "" },
                set: { session.mfCue = $0.isEmpty ? nil : $0 }
            ))
        }
    }

    @ViewBuilder
    private var blocksSection: some View {
        Section {
            if sortedBlocks.isEmpty {
                Text("No blocks yet — tap Add Block to plan the workout")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedBlocks) { block in
                    Button { blockToEdit = block } label: {
                        AddSessionBlockSummaryRow(block: block)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .contextMenu {
                        Button {
                            moveBlock(block, by: -1)
                        } label: {
                            Label("Move Up", systemImage: "arrow.up")
                        }
                        .disabled(block.id == sortedBlocks.first?.id)
                        Button {
                            moveBlock(block, by: 1)
                        } label: {
                            Label("Move Down", systemImage: "arrow.down")
                        }
                        .disabled(block.id == sortedBlocks.last?.id)
                        Button(role: .destructive) {
                            modelContext.deleteBlockCascade(block)
                        } label: {
                            Label("Delete Block", systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: moveBlocks)
                .onDelete(perform: deleteBlocks)
            }

            Button {
                showingAddBlock = true
            } label: {
                Label("Add Block", systemImage: "plus.circle.fill")
            }
            .accessibilityIdentifier("session.addBlockButton")
        } header: {
            HStack {
                Text("Blocks")
                Spacer()
#if os(iOS)
                EditButton()
                    .font(.caption)
#endif
            }
        }
    }

    // MARK: - Helpers

    private func combine(date: Date, with time: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute, .second], from: time)
        return cal.date(
            bySettingHour: comps.hour ?? 0,
            minute: comps.minute ?? 0,
            second: comps.second ?? 0,
            of: date
        ) ?? date
    }

    private func moveBlocks(from source: IndexSet, to destination: Int) {
        var blocks = sortedBlocks
        blocks.move(fromOffsets: source, toOffset: destination)
        for (index, block) in blocks.enumerated() {
            block.sortOrder = index
        }
    }

    /// Moves a single block one slot up (`offset == -1`) or down (`offset == 1`)
    /// and renumbers `sortOrder`. Backs the context menu so block reordering is
    /// reachable on macOS, where `.onMove` drag-reorder does nothing.
    private func moveBlock(_ block: SessionBlock, by offset: Int) {
        var blocks = sortedBlocks
        guard let index = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        let target = index + offset
        guard blocks.indices.contains(target) else { return }
        blocks.swapAt(index, target)
        for (index, ordered) in blocks.enumerated() {
            ordered.sortOrder = index
        }
    }

    private func deleteBlocks(at offsets: IndexSet) {
        let blocks = sortedBlocks
        for index in offsets {
            modelContext.deleteBlockCascade(blocks[index])
        }
    }
}

// MARK: - AddSessionBlockSummaryRow

/// One-line summary of a block in the create-session list. The summary text is
/// type-specific so the coach can tell distance vs time pieces vs pyramid vs
/// structural blocks at a glance. Shared between `AddSessionSheet` and
/// `EditSessionSheet` so both sheets render block rows the same way.
struct AddSessionBlockSummaryRow: View {
    let block: SessionBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displayName)
                .font(.subheadline)
            if let summary = summaryLine {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var displayName: String {
        let name = block.blockName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? block.blockType.rawValue : name
    }

    private var summaryLine: String? {
        var parts: [String] = []
        switch block.blockType {
        case .technique:
            if let dur = block.durationSeconds, dur > 0 {
                parts.append(formatDurationLabel(dur))
            }
            if let drill = block.drillName, !drill.isEmpty {
                parts.append(drill)
            }
        case .paddleDistance, .runDistance:
            if block.repetitionCount > 1 {
                parts.append("\(block.repetitionCount) reps")
            }
            if let metres = block.targetDistanceMetres, metres > 0 {
                parts.append("\(Int(metres))m")
            } else if let km = block.distanceKm, km > 0 {
                parts.append(String(format: "%.1f km", km))
            }
            if let zone = block.trainingZone {
                parts.append(zone.rawValue)
            }
        case .paddleTimePieces, .runIntervals:
            if block.repetitionCount > 1 {
                parts.append("\(block.repetitionCount) reps")
            }
            if let zone = block.trainingZone {
                parts.append(zone.rawValue)
            }
        case .paddlePyramid:
            if let pattern = block.prescribedRepDurationsSec, !pattern.isEmpty {
                if block.setCount > 1 {
                    parts.append("\(block.setCount) sets")
                }
                parts.append(pattern.map { formatDurationLabel($0) }.joined(separator: "-"))
            }
        case .weights, .circuit, .core:
            if let dur = block.durationSeconds, dur > 0 {
                parts.append(formatDurationLabel(dur))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
