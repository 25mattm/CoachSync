/// Bulk-entry sheet for logging regatta results across a team in one flow.

import SwiftUI
import SwiftData

/// Lets the coach enter one regatta's details, then fill in times for multiple athletes at once.
struct LogRegattaSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Athlete> { $0.isActive }, sort: \Athlete.lastName)
    private var allAthletes: [Athlete]

    @Query(filter: #Predicate<Team> { !$0.isArchived }, sort: \Team.teamName)
    private var teams: [Team]

    let preselectedDate: Date

    @State private var regattaName = ""
    @State private var location = ""
    @State private var regattaDate: Date
    @State private var eventDistance = 500
    @State private var selectedTeam: Team? = nil
    @State private var timeEntries: [UUID: String] = [:]
    @State private var placementEntries: [UUID: String] = [:]
    @State private var totalCompetitorsText = ""
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""

    private let distanceOptions = [200, 500, 1000, 2000, 6000]

    init(preselectedDate: Date = Date()) {
        self.preselectedDate = preselectedDate
        _regattaDate = State(initialValue: preselectedDate)
    }

    private var displayedAthletes: [Athlete] {
        guard let team = selectedTeam else { return allAthletes }
        return team.activeMembers.sorted { $0.lastName < $1.lastName }
    }

    private var validEntries: [(athlete: Athlete, timeMs: Int, placement: Int?)] {
        displayedAthletes.compactMap { athlete in
            guard let text = timeEntries[athlete.id],
                  let ms = parseTimeToMs(text) else { return nil }
            let placement = parsedPlacement(for: athlete)
            return (athlete: athlete, timeMs: ms, placement: placement)
        }
    }

    private var hasInvalidPlacements: Bool {
        displayedAthletes.contains { athlete in
            let text = placementEntries[athlete.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !text.isEmpty && parsedPlacement(for: athlete) == nil
        }
    }

    private var isValid: Bool {
        !regattaName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !validEntries.isEmpty &&
        !hasInvalidPlacements &&
        !hasInvalidTotal
    }

    /// Shared field size for this regatta, applied to every logged result.
    /// `nil` when blank; non-nil only for a positive integer.
    private var parsedTotalCompetitors: Int? {
        let text = totalCompetitorsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let n = Int(text), n > 0 else { return nil }
        return n
    }

    private var hasInvalidTotal: Bool {
        let text = totalCompetitorsText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && parsedTotalCompetitors == nil
    }

    private func parsedPlacement(for athlete: Athlete) -> Int? {
        // Bulk placements are optional, but saved placements must be positive.
        let text = placementEntries[athlete.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return nil }
        guard let placement = Int(text), placement > 0 else { return nil }
        return placement
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Regatta Info") {
                    TextField("Regatta Name", text: $regattaName)
                    TextField("Location (optional)", text: $location)
                    DatePicker("Date", selection: $regattaDate, in: ...Date.now, displayedComponents: .date)
                    Picker("Event Distance", selection: $eventDistance) {
                        // String() — Int interpolation in Text applies locale
                        // grouping and renders 1000 as "1,000".
                        ForEach(distanceOptions, id: \.self) { Text("\(String($0))m").tag($0) }
                    }
                    TextField("Total Competitors (optional)", text: $totalCompetitorsText)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                }

                Section {
                    if teams.isEmpty {
                        Text("No teams — showing all active athletes")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Team", selection: $selectedTeam) {
                            Text("All Athletes").tag(nil as Team?)
                            ForEach(teams) { team in
                                Text(team.teamName).tag(team as Team?)
                            }
                        }
                    }
                } header: {
                    Text("Athletes")
                } footer: {
                    if hasInvalidTotal {
                        Text("Total competitors must be 1 or higher.")
                    } else if hasInvalidPlacements {
                        Text("Placements must be 1 or higher.")
                    } else {
                        Text("Enter times for athletes who competed. Leave blank to skip.")
                    }
                }

                if displayedAthletes.isEmpty {
                    Section {
                        Text("No athletes in this team")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(displayedAthletes) { athlete in
                            AthleteTimeRow(
                                athlete: athlete,
                                timeText: Binding(
                                    get: { timeEntries[athlete.id] ?? "" },
                                    set: { timeEntries[athlete.id] = $0 }
                                ),
                                placementText: Binding(
                                    get: { placementEntries[athlete.id] ?? "" },
                                    set: { placementEntries[athlete.id] = $0 }
                                )
                            )
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Log Regatta Results")
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
            .alert("Couldn't Save Results", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
    }

    private func save() {
        let name = regattaName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)

        for entry in validEntries {
            let result = RegattaResult(
                regattaName: name,
                location: trimmedLocation.isEmpty ? nil : trimmedLocation,
                regattaDate: regattaDate,
                eventDistance: eventDistance,
                placement: entry.placement,
                totalCompetitors: parsedTotalCompetitors,
                resultTimeMs: entry.timeMs,
                athlete: entry.athlete
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

// MARK: - Athlete Time Row

/// One row in the bulk time-entry list.
private struct AthleteTimeRow: View {
    let athlete: Athlete
    @Binding var timeText: String
    @Binding var placementText: String

    private var isValidTime: Bool {
        timeText.isEmpty || parseTimeToMs(timeText) != nil
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(athlete.firstName) \(athlete.lastName)")
                    .font(.subheadline)
                Text(athlete.ageCategory)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("#", text: $placementText)
                .frame(width: 36)
                .multilineTextAlignment(.trailing)
#if os(iOS)
                .keyboardType(.numberPad)
#endif
            Divider()
                .frame(height: 16)
            TextField("MM:SS.ms", text: $timeText)
                .frame(width: 90)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(isValidTime ? Color.primary : Color.red)
#if os(iOS)
                .keyboardType(.numbersAndPunctuation)
#endif
        }
    }
}
