/// Type-driven sheet for creating or editing a `SessionBlock`.
///
/// Each `BlockType` exposes a different set of input fields — distance blocks
/// ask for reps + distance, time-pieces ask for reps + duration + a "track time?"
/// toggle, pyramids use a chip editor for variable per-rep durations, and
/// structural blocks (warmup/cooldown/technique) just take a duration. The form
/// switches the relevant section based on `blockType`.

import SwiftUI
import SwiftData

struct AddBlockSheet: View {
    let session: CoachSession
    var existingBlock: SessionBlock? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Type + naming
    @State private var blockType: BlockType = .paddleDistance
    @State private var blockName: String = ""
    @State private var coachNote: String = ""
    @State private var trainingZone: TrainingZone? = nil

    // Reps + per-rep distance/time
    @State private var repCount: Int = 1
    @State private var distanceMetres: String = ""
    @State private var distanceKm: String = ""
    @State private var useKmOverride: Bool = false
    @State private var perRepMinutes: Int = 4
    @State private var perRepSeconds: Int = 0

    // Rest interval (between reps or sets)
    @State private var restMinutes: Int = 2
    @State private var restSeconds: Int = 0

    // Time-tracking toggle (false = check-off mode)
    @State private var requiresTimeEntry: Bool = true

    // Pyramid
    @State private var pyramidDurationsSec: [Int] = [240, 120, 60, 30, 60, 120, 240]
    @State private var setCount: Int = 4

    // Structural / land blocks
    @State private var blockMinutes: Int = 10
    @State private var blockSeconds: Int = 0
    @State private var drillName: String = ""

    // Save error
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    private var isEditing: Bool { existingBlock != nil }

    // Seed `blockType` from the existing block (when editing) so the type
    // picker starts at its final value. Without this, `blockType` would default
    // to `.paddleDistance` and then change to the loaded value during
    // `.onAppear`, firing `.onChange(of: blockType)` and clobbering the
    // `requiresTimeEntry` value that `loadFromExisting()` just restored.
    init(session: CoachSession, existingBlock: SessionBlock? = nil) {
        self.session = session
        self.existingBlock = existingBlock
        _blockType = State(initialValue: existingBlock?.blockType ?? .paddleDistance)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Block type", selection: $blockType) {
                        ForEach(BlockType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                blockTypeSpecificSection
                Section("Name & Note") {
                    TextField("Name", text: $blockName, prompt: Text(autoName))
                    TextField("Coach note (optional)",
                              text: $coachNote, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(isEditing ? "Edit Block" : "Add Block")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { commit() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                        .accessibilityIdentifier("block.addButton")
                }
            }
            .alert("Save Error", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        }
        .onAppear { loadFromExisting() }
        .onChange(of: blockType) { _, newType in
            // Pyramids default to no per-rep time tracking; switching to any
            // other type restores it (otherwise the toggle stays stuck off).
            requiresTimeEntry = (newType != .paddlePyramid)
        }
    }

    // MARK: - Type-specific sections

    @ViewBuilder
    private var blockTypeSpecificSection: some View {
        switch blockType {
        case .paddleDistance, .runDistance:
            distanceFieldsSection
        case .paddleTimePieces, .runIntervals:
            timePiecesFieldsSection
        case .paddlePyramid:
            pyramidFieldsSection
        case .weights, .core:
            // Coach-note-only — handled in the Name & Note section.
            EmptyView()
        case .circuit:
            circuitFieldsSection
        case .technique:
            techniqueFieldsSection
        }
    }

    @ViewBuilder
    private var distanceFieldsSection: some View {
        Section("Distance") {
            Stepper("Reps: \(repCount)", value: $repCount, in: 1...50)
            HStack {
                Text("Distance per rep (m)")
                Spacer()
                TextField("e.g. 1000", text: $distanceMetres)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110)
                    .accessibilityIdentifier("block.distanceField")
            }
            if let totalKm = computedTotalKm {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total distance")
                            .font(.subheadline)
                        Text(String(format: "%.2f km", totalKm))
                            .font(.caption)
                            .foregroundStyle(Color.readableSecondary)
                    }
                    Spacer()
                    Toggle("Override", isOn: $useKmOverride)
                        .labelsHidden()
                }
                if useKmOverride {
                    HStack {
                        Text("Total km")
                        Spacer()
                        TextField("Enter km", text: $distanceKm)
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110)
                    }
                }
            }
            if repCount > 1 {
                restRow
            }
            if blockType == .paddleDistance {
                zonePicker
            }
        }
    }

    @ViewBuilder
    private var timePiecesFieldsSection: some View {
        Section("Time pieces") {
            Stepper("Reps: \(repCount)", value: $repCount, in: 1...50)
            HStack {
                Text("Each piece")
                Spacer()
                Stepper("\(perRepMinutes)m", value: $perRepMinutes, in: 0...59)
                    .fixedSize()
                Stepper("\(perRepSeconds)s", value: $perRepSeconds, in: 0...59, step: 5)
                    .fixedSize()
            }
            if repCount > 1 { restRow }
            if blockType == .paddleTimePieces {
                zonePicker
            }
            Toggle("Track time per rep", isOn: $requiresTimeEntry)
        }
    }

    @ViewBuilder
    private var pyramidFieldsSection: some View {
        Section {
            TimeChipEditor(durationsSec: $pyramidDurationsSec)
        } header: {
            Text("Per-rep durations (one set)")
        } footer: {
            Text("Tap a chip to edit, ✕ to remove. Drag chips for order via the Edit menu.")
                .font(.caption2)
        }
        Section("Pyramid settings") {
            Stepper("Sets: \(setCount)", value: $setCount, in: 1...10)
            restRow
            zonePicker
            Toggle("Track time per rep", isOn: $requiresTimeEntry)
        }
    }

    @ViewBuilder
    private var circuitFieldsSection: some View {
        Section("Circuit") {
            durationStepper
        }
    }

    @ViewBuilder
    private var techniqueFieldsSection: some View {
        Section("Technique") {
            TextField("Drill name (e.g. 'Catch position')", text: $drillName)
            durationStepper
        }
    }

    // MARK: - Reusable rows

    @ViewBuilder
    private var restRow: some View {
        HStack {
            Text("Rest between reps")
            Spacer()
            Stepper("\(restMinutes)m", value: $restMinutes, in: 0...59)
                .fixedSize()
            Stepper("\(restSeconds)s", value: $restSeconds, in: 0...59, step: 15)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var durationStepper: some View {
        HStack {
            Text("Duration")
            Spacer()
            Stepper("\(blockMinutes)m", value: $blockMinutes, in: 0...120)
                .fixedSize()
            Stepper("\(blockSeconds)s", value: $blockSeconds, in: 0...59, step: 5)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var zonePicker: some View {
        Picker("Training zone", selection: $trainingZone) {
            Text("No zone").tag(nil as TrainingZone?)
            ForEach(TrainingZone.allCases, id: \.self) { zone in
                HStack {
                    Circle()
                        .fill(zone.color)
                        .frame(width: 8, height: 8)
                    Text(zone.rawValue)
                }
                .tag(zone as TrainingZone?)
            }
        }
    }

    // MARK: - Computed helpers

    private var computedTotalKm: Double? {
        guard let m = Double(distanceMetres), m > 0 else { return nil }
        return Double(repCount) * m / 1000.0
    }

    private var autoName: String {
        switch blockType {
        case .paddleDistance, .runDistance:
            if let m = Double(distanceMetres), m > 0 {
                if repCount > 1 {
                    return "\(repCount) × \(Int(m))m"
                }
                if let km = computedTotalKm {
                    return String(format: "%.1fk %@",
                                  km, blockType == .paddleDistance ? "Paddle" : "Run")
                }
            }
            return blockType.rawValue
        case .paddleTimePieces, .runIntervals:
            let dur = formatChipDuration(perRepMinutes * 60 + perRepSeconds)
            return "\(repCount) × \(dur)"
        case .paddlePyramid:
            return pyramidDurationsSec.map { formatChipDuration($0) }.joined(separator: "-")
        case .weights, .circuit, .core:
            return blockType.rawValue
        case .technique:
            return drillName.isEmpty ? "Technique" : drillName
        }
    }

    private var isValid: Bool {
        switch blockType {
        case .paddleDistance, .runDistance:
            return Double(distanceMetres) ?? 0 > 0
        case .paddleTimePieces, .runIntervals:
            return (perRepMinutes * 60 + perRepSeconds) > 0
        case .paddlePyramid:
            return !pyramidDurationsSec.isEmpty
        case .technique:
            return !drillName.trimmingCharacters(in: .whitespaces).isEmpty
        case .weights, .core, .circuit:
            return true
        }
    }

    // MARK: - Load + commit

    /// Populates @State from an existing block when in edit mode.
    private func loadFromExisting() {
        guard let block = existingBlock else { return }
        blockType = block.blockType
        blockName = block.blockName
        coachNote = block.coachNote ?? ""
        trainingZone = block.trainingZone
        repCount = max(block.repetitionCount, 1)
        if let metres = block.targetDistanceMetres {
            distanceMetres = String(Int(metres))
        }
        if let km = block.distanceKm {
            distanceKm = String(format: "%.2f", km)
            useKmOverride = true
        }
        if let dur = block.durationSeconds {
            blockMinutes = dur / 60
            blockSeconds = dur % 60
        }
        if let pattern = block.prescribedRepDurationsSec {
            pyramidDurationsSec = pattern
        }
        setCount = max(block.setCount, 1)
        requiresTimeEntry = block.requiresTimeEntry
        if let drill = block.drillName {
            drillName = drill
        }
        if let rest = block.restIntervalSeconds {
            restMinutes = rest / 60
            restSeconds = rest % 60
        }
    }

    /// Rep capacity the sheet will save for the current type and state — the
    /// number of per-rep slots the logger will render. Pyramid capacity comes
    /// from pattern × sets (what the check-off grid actually draws), and types
    /// without per-rep tracking have no slot capacity at all.
    private var plannedSlotCapacity: Int {
        switch blockType {
        case .paddleDistance, .runDistance, .paddleTimePieces, .runIntervals:
            return repCount
        case .paddlePyramid:
            return pyramidDurationsSec.count * max(setCount, 1)
        case .weights, .circuit, .core, .technique:
            return 0
        }
    }

    /// Saves the block (creating a new one or mutating the existing one).
    private func commit() {
        // Refuse an edit that would strand recorded results beyond the block's
        // visible rep capacity — shrinking reps below a filled slot, or
        // switching to a type without per-rep tracking. Mirrors the app's
        // deletion guards: recorded coaching data is never silently destroyed,
        // and never left feeding analytics from slots the logger won't render.
        if let existing = existingBlock {
            let highestFilled = existing.highestFilledRepNumber
            if highestFilled > plannedSlotCapacity {
                saveErrorMessage = plannedSlotCapacity == 0
                    ? "This block has recorded results. Clear them in the logger before changing it to a type without per-rep tracking."
                    : "Recorded results exist up to rep \(highestFilled). Clear them in the logger before reducing the block below \(highestFilled) reps."
                showSaveError = true
                return
            }
        }

        let block: SessionBlock
        if let existing = existingBlock {
            block = existing
            block.blockType = blockType
        } else {
            let nextOrder = ((session.sessionBlocks ?? []).map(\.sortOrder).max() ?? -1) + 1
            block = SessionBlock(
                blockName: "",
                blockType: blockType,
                sortOrder: nextOrder,
                session: session
            )
            modelContext.insert(block)
        }

        let trimmedName = blockName.trimmingCharacters(in: .whitespaces)
        block.blockName = trimmedName.isEmpty ? autoName : trimmedName
        block.coachNote = coachNote.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : coachNote.trimmingCharacters(in: .whitespaces)
        block.trainingZone = trainingZone

        // Reset and apply type-specific fields. Existing rows are mutated, so
        // explicitly clear fields that aren't relevant to the new type.
        applyTypeSpecificFields(to: block)

        // Pre-generate per-athlete per-rep PerformanceRecord slots for newly
        // created trackable blocks when attendance is already known. During the
        // create-session flow, attendance is empty — slots are generated later
        // by SessionLogger when transitioning out of the Attendance phase
        // (handled in Phase 1.4).
        if existingBlock == nil
            && blockType.capturesPerRepData
            && session.attendanceRecords?.isEmpty == false {
            generateSlots(for: block)
        }

        // Shrinking an existing block leaves pre-generated slots stranded
        // beyond the new rep capacity; delete the unfilled ones so they stop
        // feeding analytics invisibly. (Filled ones can't reach here — the
        // guard above refused the save. Growing needs nothing: the logger
        // backfills missing slots on next entry.)
        if existingBlock != nil {
            modelContext.pruneUnfilledSlots(of: block, beyondRep: plannedSlotCapacity)
        }

        do {
            try SyncStore.save(modelContext)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }

    private func generateSlots(for block: SessionBlock) {
        let presentAthletes = (session.attendanceRecords ?? [])
            .filter { $0.status == .present }
            .compactMap { $0.athlete }
        let totalReps = max(block.repetitionCount, 1)
        for athlete in presentAthletes {
            for rep in 1...totalReps {
                let slot = PerformanceRecord(
                    athlete: athlete,
                    sessionBlock: block,
                    repNumber: rep
                )
                modelContext.insert(slot)
            }
        }
    }

    /// Writes the block's fields based on the current type, clearing fields
    /// that don't apply (in case the user changed type during editing).
    private func applyTypeSpecificFields(to block: SessionBlock) {
        // Wipe by default; specific cases set what's relevant.
        block.repetitionCount = 1
        block.targetDistanceMetres = nil
        block.distanceKm = nil
        block.restIntervalSeconds = nil
        block.requiresTimeEntry = true
        block.prescribedRepDurationsSec = nil
        block.setCount = 1
        block.durationSeconds = nil
        block.drillName = nil

        switch blockType {
        case .paddleDistance, .runDistance:
            block.repetitionCount = repCount
            if let m = Double(distanceMetres), m > 0 {
                block.targetDistanceMetres = m
            }
            if useKmOverride, let km = Double(distanceKm), km > 0 {
                block.distanceKm = km
            }
            if repCount > 1 {
                block.restIntervalSeconds = restMinutes * 60 + restSeconds
            }

        case .paddleTimePieces, .runIntervals:
            block.repetitionCount = repCount
            block.durationSeconds = perRepMinutes * 60 + perRepSeconds
            if repCount > 1 {
                block.restIntervalSeconds = restMinutes * 60 + restSeconds
            }
            block.requiresTimeEntry = requiresTimeEntry

        case .paddlePyramid:
            block.prescribedRepDurationsSec = pyramidDurationsSec
            block.setCount = max(setCount, 1)
            block.repetitionCount = pyramidDurationsSec.count * max(setCount, 1)
            block.restIntervalSeconds = restMinutes * 60 + restSeconds
            block.requiresTimeEntry = requiresTimeEntry

        case .circuit:
            block.durationSeconds = blockMinutes * 60 + blockSeconds

        case .technique:
            block.durationSeconds = blockMinutes * 60 + blockSeconds
            block.drillName = drillName.trimmingCharacters(in: .whitespaces)

        case .weights, .core:
            // Note-driven only — coachNote already set above.
            break
        }
    }
}

// MARK: - TimeChipEditor

/// Renders an array of duration chips with edit + remove controls.
/// Used by paddle pyramid blocks.
private struct TimeChipEditor: View {
    @Binding var durationsSec: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 70, maximum: 110), spacing: 6)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(durationsSec.indices, id: \.self) { index in
                    TimeChip(
                        seconds: durationsSec[index],
                        onEdit: { durationsSec[index] = $0 },
                        onDelete: { durationsSec.remove(at: index) }
                    )
                }
            }
            Button {
                durationsSec.append(60)
            } label: {
                Label("Add rep", systemImage: "plus.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

private struct TimeChip: View {
    let seconds: Int
    let onEdit: (Int) -> Void
    let onDelete: () -> Void
    @State private var editing = false

    var body: some View {
        HStack(spacing: 4) {
            Button { editing = true } label: {
                Text(formatChipDuration(seconds))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            Button { onDelete() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.readableSecondary)
            .accessibilityLabel("Remove chip")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.18), in: Capsule())
        .sheet(isPresented: $editing) {
            DurationEditor(initialSeconds: seconds) {
                onEdit($0)
                editing = false
            }
#if os(macOS)
            .frame(minWidth: 320, minHeight: 240)
#endif
        }
    }
}

private struct DurationEditor: View {
    let initialSeconds: Int
    let onCommit: (Int) -> Void

    @State private var minutes: Int
    @State private var seconds: Int
    @Environment(\.dismiss) private var dismiss

    init(initialSeconds: Int, onCommit: @escaping (Int) -> Void) {
        self.initialSeconds = initialSeconds
        self.onCommit = onCommit
        _minutes = State(initialValue: initialSeconds / 60)
        _seconds = State(initialValue: initialSeconds % 60)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Duration") {
                    Stepper("Minutes: \(minutes)", value: $minutes, in: 0...59)
                    Stepper("Seconds: \(seconds)", value: $seconds, in: 0...59, step: 5)
                }
                Section {
                    HStack {
                        Spacer()
                        Text(formatChipDuration(minutes * 60 + seconds))
                            .font(.title3)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Edit Duration")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onCommit(minutes * 60 + seconds)
                    }
                    .fontWeight(.semibold)
                    .disabled(minutes == 0 && seconds == 0)
                }
            }
        }
    }
}
