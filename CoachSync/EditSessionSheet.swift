/// Edits session metadata and block list. Changes commit live via @Bindable
/// rather than staged in @State, so the sheet behaves the same way for
/// metadata edits and block edits — both go straight to the model and the
/// "Done" button only dismisses. This unified semantic replaces an earlier
/// Cancel/Save flow where metadata staged through @State while block edits
/// committed immediately, which created a confusing inconsistency.

import SwiftUI
import SwiftData

/// Modal form for updating a session.
struct EditSessionSheet: View {
    @Bindable var session: CoachSession
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Team.teamName) private var teams: [Team]

    @State private var showingAddBlock = false
    @State private var blockToEdit: SessionBlock? = nil

    // Save error surfaced when SyncStore.save throws on Done.
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    // Shown when the coach tries to delete a block that holds recorded rep results.
    @State private var blockDeleteBlocked = false

    /// Blocks sorted by their stored sort order so the coach sees the same
    /// sequence the session logger will run.
    private var sortedBlocks: [SessionBlock] {
        (session.sessionBlocks ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            Form {
                practiceInfoSection
                workoutDescriptionSection
                mfCueSection
                teamSection
                blocksSection
            }
            .navigationTitle("Edit Practice")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // A persisted blank name would make this session look
                        // like a leaked draft to AddSessionSheet's sweep —
                        // auto-fill it exactly like the create flow does.
                        if session.sessionName.trimmingCharacters(in: .whitespaces).isEmpty {
                            session.sessionName = autoSessionName(for: session)
                        }
                        do {
                            try SyncStore.save(modelContext)
                            dismiss()
                        } catch {
                            saveErrorMessage = error.localizedDescription
                            showSaveError = true
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Save Error", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
            .alert("Can't Delete Block", isPresented: $blockDeleteBlocked) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This block has recorded rep results. Deleting it would discard those logged "
                     + "times — clear the recorded reps in the session logger first if you need to "
                     + "remove the block.")
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
            // Keep the time-of-day portion of start/end attached to whichever
            // date the coach picks. Without this, editing the date leaves
            // startTime/endTime pointing at the old calendar day and the
            // session appears at the wrong slot in calendar/schedule views.
            .onChange(of: session.scheduledDate) { _, newDate in
                if let start = session.startTime {
                    session.startTime = combine(date: newDate, with: start)
                }
                if let end = session.endTime {
                    session.endTime = combine(date: newDate, with: end)
                }
            }
        }
    }

    // MARK: - Form sections

    @ViewBuilder
    private var practiceInfoSection: some View {
        Section("Practice Info") {
            TextField("Practice Name", text: $session.sessionName)
            DatePicker("Date", selection: $session.scheduledDate,
                       displayedComponents: .date)
            // Clamp at the binding level so the live-commit @Bindable design
            // can't persist an inverted time range. Picking a Start that would
            // overrun End pushes End forward; picking an End at or before
            // Start snaps it to Start + 1 minute.
            DatePicker("Start Time", selection: Binding(
                get: { session.startTime ?? defaultedTime(hour: 6) },
                set: { newStart in
                    session.startTime = newStart
                    if let end = session.endTime, end <= newStart {
                        session.endTime = newStart.addingTimeInterval(60)
                    }
                }
            ), displayedComponents: .hourAndMinute)
            DatePicker("End Time", selection: Binding(
                get: { session.endTime ?? defaultedTime(hour: 8) },
                set: { newEnd in
                    if let start = session.startTime, newEnd <= start {
                        session.endTime = start.addingTimeInterval(60)
                    } else {
                        session.endTime = newEnd
                    }
                }
            ), displayedComponents: .hourAndMinute)
        }
    }

    @ViewBuilder
    private var workoutDescriptionSection: some View {
        Section("Workout Description") {
            TextField("Describe the planned workout...",
                      text: Binding(
                        get: { session.teamNote ?? "" },
                        set: { session.teamNote = $0.isEmpty ? nil : $0 }
                      ),
                      axis: .vertical)
                .lineLimit(4...8)
        }
    }

    @ViewBuilder
    private var mfCueSection: some View {
        Section("MF Cue") {
            HStack {
                TextField("e.g. Blade before rotation",
                          text: Binding(
                            get: { session.mfCue ?? "" },
                            set: { session.mfCue = $0.isEmpty ? nil : $0 }
                          ))
                if session.mfCue?.isEmpty == false {
                    Button {
                        session.mfCue = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var teamSection: some View {
        Section("Team") {
            if teams.isEmpty {
                Text("No teams yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Team", selection: $session.team) {
                    Text("All Athletes").tag(nil as Team?)
                    ForEach(teams) { team in
                        Text(team.teamName).tag(team as Team?)
                    }
                }
            }
        }
    }

    // MARK: - Blocks section

    /// Mirrors the blocks section in `AddSessionSheet` so editing a session
    /// gives the coach the same affordances as creating one: add, reorder,
    /// edit, and delete blocks. Deletions go through `deleteBlockCascade`
    /// so any per-rep performance data the coach already logged is removed
    /// alongside the block instead of being orphaned.
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
                            deleteBlock(block)
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
            deleteBlock(blocks[index])
        }
    }

    /// Deletes a block, refusing when it holds recorded rep results (a time, DNS, or DNF). Mirrors
    /// the backend's `assertDeletable` guard and `AddBlockSheet`'s shrink/retype edit-guard — a
    /// logged block can't be silently discarded; the coach clears its recorded reps first.
    private func deleteBlock(_ block: SessionBlock) {
        guard block.highestFilledRepNumber == 0 else {
            blockDeleteBlocked = true
            return
        }
        modelContext.deleteBlockCascade(block)
    }

    // MARK: - Helpers

    /// Snaps the time-of-day from `time` onto the calendar day from `date`.
    /// Falls back to `date` if the time components can't be extracted.
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

    /// Default fallback time used to seed the DatePicker when the session
    /// has no startTime/endTime yet (rare — usually populated at creation).
    private func defaultedTime(hour: Int) -> Date {
        Calendar.current.date(
            bySettingHour: hour, minute: 0, second: 0,
            of: session.scheduledDate
        ) ?? Date()
    }
}
