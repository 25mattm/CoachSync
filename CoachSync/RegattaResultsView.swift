/// Shows an athlete's regatta history and supports logging new race results.
import SwiftUI
import SwiftData

/// Lists regatta results grouped by season.
struct RegattaResultsView: View {
    @Bindable var athlete: Athlete

    @Environment(\.modelContext) private var modelContext

    @State private var showingNewResult = false
    @State private var showingLogRegatta = false
    @State private var resultToDelete: RegattaResult? = nil
    @State private var resultToEdit: RegattaResult? = nil
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    private var sortedResults: [RegattaResult] {
        (athlete.regattaResults ?? []).sorted { lhs, rhs in
            if lhs.regattaDate == rhs.regattaDate {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.regattaDate > rhs.regattaDate
        }
    }

    private var groupedBySeason: [(season: Int, results: [RegattaResult])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sortedResults) {
            SeasonContext.year(of: $0.regattaDate, calendar: calendar)
        }
        return grouped
            .map { (season: $0.key, results: $0.value) }
            .sorted { $0.season > $1.season }
    }

    private var personalBestIDs: Set<UUID> {
        let grouped = Dictionary(grouping: athlete.regattaResults ?? []) { $0.eventDistance }
        var ids = Set<UUID>()
        for (_, results) in grouped {
            if let best = results.min(by: { $0.resultTimeMs < $1.resultTimeMs }) {
                ids.insert(best.id)
            }
        }
        return ids
    }

    var body: some View {
        List {
            if groupedBySeason.isEmpty {
                EmptyCard(message: "No regatta results recorded yet. Tap + to log one.",
                          systemImage: "flag.checkered")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(groupedBySeason, id: \.season) { group in
                    Section(String(group.season)) {
                        ForEach(group.results) { result in
                            RegattaResultCard(result: result, isPersonalBest: personalBestIDs.contains(result.id))
                                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .leading) {
                                    Button {
                                        resultToEdit = result
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(Color.accentColor)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        resultToDelete = result
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button {
                                        resultToEdit = result
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        resultToDelete = result
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
#if os(iOS)
        .listStyle(.insetGrouped)
#else
        .listStyle(.inset)
#endif
        .navigationTitle("Regatta Results")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        showingNewResult = true
                    } label: {
                        Label("Single Result", systemImage: "person")
                    }
                    Button {
                        showingLogRegatta = true
                    } label: {
                        Label("Log Team Results", systemImage: "flag.checkered")
                    }
                } label: {
                    Label("Add Result", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewResult) {
            NewRegattaResultSheet(athlete: athlete)
#if os(macOS)
                .frame(minWidth: 520, minHeight: 640)
#endif
        }
        .sheet(isPresented: $showingLogRegatta) {
            LogRegattaSheet()
#if os(macOS)
                .frame(minWidth: 520, minHeight: 600)
#endif
        }
        .sheet(item: $resultToEdit) { result in
            NewRegattaResultSheet(athlete: athlete, existingResult: result)
#if os(macOS)
                .frame(minWidth: 520, minHeight: 640)
#endif
        }
        .confirmationDialog(
            "Delete this result?",
            isPresented: Binding(
                get: { resultToDelete != nil },
                set: { if !$0 { resultToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Result", role: .destructive) {
                if let result = resultToDelete {
                    modelContext.delete(result)
                    do {
                        try SyncStore.save(modelContext)
                    } catch {
                        saveErrorMessage = error.localizedDescription
                        showSaveError = true
                    }
                }
                resultToDelete = nil
            }
            Button("Cancel", role: .cancel) { resultToDelete = nil }
        } message: {
            if let result = resultToDelete {
                Text("\(result.regattaName) · \(String(result.eventDistance))m · \(result.formattedTime)")
            }
        }
        .alert("Couldn't Delete Result", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }
}

/// Card view for one regatta result.
struct RegattaResultCard: View {
    let result: RegattaResult
    let isPersonalBest: Bool

    private var placementText: String? {
        guard let placement = result.placement else { return nil }
        guard let total = result.totalCompetitors else {
            return String.ordinal(placement)
        }
        return "\(String.ordinal(placement)) of \(total)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.regattaName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if isPersonalBest {
                    Text("PB")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.yellow.opacity(0.2))
                        .foregroundStyle(Color.readableOrange)
                        .clipShape(Capsule())
                }
            }

            HStack {
                Text(result.regattaDate.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.caption)
                    .foregroundStyle(Color.readableSecondary)
                if let location = result.location, !location.isEmpty {
                    Text("• \(location)")
                        .font(.caption)
                        .foregroundStyle(Color.readableSecondary)
                }
            }

            HStack {
                // String() — Int interpolation in Text applies locale grouping
                // and renders 1000 as "1,000".
                Text("\(String(result.eventDistance))m")
                    .font(.caption)
                    .foregroundStyle(Color.readableSecondary)
                Spacer()
                Text(result.formattedTime)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }

            if let placementText {
                Text(placementText)
                    .font(.caption)
                    .foregroundStyle(Color.readableSecondary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Collects a new regatta result or edits an existing one.
struct NewRegattaResultSheet: View {
    let athlete: Athlete
    let existingResult: RegattaResult?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var regattaName: String
    @State private var location: String
    @State private var regattaDate: Date
    @State private var eventDistance: Int
    @State private var timeText: String
    @State private var placementText: String
    @State private var totalCompetitorsText: String
    @State private var notes: String
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""

    private let distanceOptions = [200, 500, 1000, 2000, 6000]

    init(athlete: Athlete, existingResult: RegattaResult? = nil) {
        self.athlete = athlete
        self.existingResult = existingResult
        _regattaName = State(initialValue: existingResult?.regattaName ?? "")
        _location = State(initialValue: existingResult?.location ?? "")
        _regattaDate = State(initialValue: existingResult?.regattaDate ?? Date())
        _eventDistance = State(initialValue: existingResult?.eventDistance ?? 500)
        _timeText = State(initialValue: existingResult.map { formatMillisecondsForDisplay($0.resultTimeMs) } ?? "")
        _placementText = State(initialValue: existingResult?.placement.map { String($0) } ?? "")
        _totalCompetitorsText = State(initialValue: existingResult?.totalCompetitors.map { String($0) } ?? "")
        _notes = State(initialValue: existingResult?.notes ?? "")
    }

    private var parsedTimeMs: Int? {
        parseTimeToMs(timeText)
    }

    private var isValid: Bool {
        !regattaName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        parsedTimeMs != nil &&
        placementValidationMessage == nil
    }

    private var placementValidationMessage: String? {
        // Placements are optional, but when present they need to describe a real race result.
        let placement = placementText.trimmingCharacters(in: .whitespacesAndNewlines)
        let total = totalCompetitorsText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !placement.isEmpty || !total.isEmpty else { return nil }
        guard let placementValue = Int(placement), placementValue > 0 else {
            return "Placement must be 1 or higher."
        }

        if !total.isEmpty {
            guard let totalValue = Int(total), totalValue > 0 else {
                return "Total competitors must be 1 or higher."
            }
            if placementValue > totalValue {
                return "Placement cannot be greater than total competitors."
            }
        }

        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Result Details") {
                    TextField("Regatta Name", text: $regattaName)
                    TextField("Location (optional)", text: $location)
                    DatePicker("Date", selection: $regattaDate, in: ...Date.now, displayedComponents: .date)
                    Picker("Event Distance", selection: $eventDistance) {
                        ForEach(distanceOptions, id: \.self) { option in
                            Text("\(String(option))m").tag(option)
                        }
                    }
                }

                Section("Time") {
                    TextField("MM:SS.ms", text: $timeText)
#if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
#endif
                    if !timeText.isEmpty && parsedTimeMs == nil {
                        Text("Enter a valid time format (e.g. 1:52.34)")
                            .font(.caption)
                            .foregroundStyle(Color.readableRed)
                    }
                }

                Section("Placement (Optional)") {
                    TextField("Finishing Position", text: $placementText)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                    TextField("Total Competitors", text: $totalCompetitorsText)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                    if let placementValidationMessage {
                        Text(placementValidationMessage)
                            .font(.caption)
                            .foregroundStyle(Color.readableRed)
                    }
                }

                Section("Notes (Optional)") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(existingResult == nil ? "Log Regatta Result" : "Edit Regatta Result")
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
            .alert("Couldn't Save Regatta Result", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
    }

    private func save() {
        guard let resultTimeMs = parsedTimeMs else { return }

        // Trim before parsing — validation trims, so " 3" must not silently
        // save a nil placement.
        let placement = Int(placementText.trimmingCharacters(in: .whitespacesAndNewlines))
        let totalCompetitors = Int(totalCompetitorsText.trimmingCharacters(in: .whitespacesAndNewlines))
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = regattaName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = existingResult {
            existing.regattaName = trimmedName
            existing.location = trimmedLocation.isEmpty ? nil : trimmedLocation
            existing.regattaDate = regattaDate
            existing.eventDistance = eventDistance
            existing.placement = placement
            existing.totalCompetitors = totalCompetitors
            existing.resultTimeMs = resultTimeMs
            existing.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        } else {
            let result = RegattaResult(
                regattaName: trimmedName,
                location: trimmedLocation.isEmpty ? nil : trimmedLocation,
                regattaDate: regattaDate,
                eventDistance: eventDistance,
                placement: placement,
                totalCompetitors: totalCompetitors,
                resultTimeMs: resultTimeMs,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                athlete: athlete
            )
            modelContext.insert(result)
        }

        do {
            try SyncStore.save(modelContext)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showingSaveError = true
        }
    }
}
