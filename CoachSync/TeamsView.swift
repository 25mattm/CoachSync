/// Displays team management flows, roster summaries, and team-level training load.

import SwiftUI
import SwiftData

/// Root view for active and archived teams.
struct TeamsView: View {
    @Environment(\.modelContext) private var modelContext
    /// Text on an accent-filled button: the dark-mode accent is a pale pink, where white text
    /// falls to ~2.3:1 contrast, so it switches to black there (~9:1).
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Team.teamName) private var teams: [Team]
    @State private var showingAddTeam = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    var activeTeams: [Team] { teams.filter { !$0.isArchived } }
    var archivedTeams: [Team] { teams.filter { $0.isArchived } }

    /// Archives a team and persists the change, surfacing any save error.
    private func archiveTeam(_ team: Team) {
        team.isArchived = true
        do {
            try SyncStore.save(modelContext)
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeTeams.isEmpty {
                    ScrollsWhenTooTall {
                        VStack(spacing: 20) {
                            Spacer()
                            Image(systemName: "person.3")
                                .font(.system(.largeTitle))
                                .imageScale(.large)
                                .foregroundStyle(Color.readableSecondary)
                            Text("No Teams Yet")
                                .font(.title2).fontWeight(.bold)
                            Text("Create a team and add athletes\nto start logging practices.")
                                .font(.subheadline)
                                .foregroundStyle(Color.readableSecondary)
                                .multilineTextAlignment(.center)
                            Button {
                                showingAddTeam = true
                            } label: {
                                Label("Create First Team", systemImage: "plus")
                                    .font(.headline)
                                    .foregroundStyle(colorScheme == .dark ? .black : .white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 14)
                                    .background(Color.accentColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            Spacer()
                        }
                        .padding()
                    }
                } else {
                    List {
                        Section {
                            ForEach(activeTeams) { team in
                                NavigationLink(destination: TeamDetailView(team: team)) {
                                    TeamRow(team: team)
                                }
                                .contextMenu {
                                    Button {
                                        archiveTeam(team)
                                    } label: {
                                        Label("Archive Team", systemImage: "archivebox")
                                    }
                                }
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    archiveTeam(activeTeams[index])
                                }
                            }
                        } header: {
                            Text("\(activeTeams.count) active team\(activeTeams.count == 1 ? "" : "s")")
                        }

                        if !archivedTeams.isEmpty {
                            Section("Archived") {
                                ForEach(archivedTeams) { team in
                                    NavigationLink(destination: TeamDetailView(team: team)) {
                                        TeamRow(team: team)
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
                }
            }
            .navigationTitle("Teams")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingAddTeam = true
                    } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                    .accessibilityLabel("Add team")
                }
            }
            .sheet(isPresented: $showingAddTeam) {
                AddTeamSheet()
#if os(macOS)
                    .frame(minWidth: 460, minHeight: 420)
#endif
            }
            .alert("Save Error", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
    }
}

// MARK: - Team Row

/// Compact summary row for a team.
struct TeamRow: View {
    let team: Team

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "person.3.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(team.teamName)
                    .font(.body).fontWeight(.medium)

                HStack(spacing: 8) {
                    Text("\(team.activeMembers.count) athlete\(team.activeMembers.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Color.readableSecondary)

                    if team.isArchived {
                        Text("Archived")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.filledGray)
                            .clipShape(Capsule())
                    }
                }

                let categories = Dictionary(grouping: team.activeMembers) { $0.ageCategory }
                if !categories.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(SeasonContext.ageCategoryDisplayOrder, id: \.self) { cat in
                            if let count = categories[cat]?.count {
                                Text("\(cat): \(count)")
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Team Detail View

/// Shows roster management and seasonal training summaries for a team.
struct TeamDetailView: View {
    @Bindable var team: Team
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Athlete> { $0.isActive },
           sort: \Athlete.lastName) private var allAthletes: [Athlete]

    @State private var showingAddMember = false
    @State private var showingEditTeam = false
    @State private var athleteToRemove: Athlete? = nil
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    var activeMembers: [Athlete] {
        team.activeMembers.sorted { $0.lastName < $1.lastName }
    }

    var availableAthletes: [Athlete] {
        let memberIDs = Set(team.activeMembers.map { $0.id })
        return allAthletes.filter { !memberIDs.contains($0.id) }
    }

    /// Completed sessions in the current year, used for team load summaries.
    var seasonalSessions: [CoachSession] {
        SeasonContext.completedSessions(from: team.sessions ?? [])
    }

    /// Completed sessions from the last seven days, excluding future sessions.
    var weeklySessions: [CoachSession] {
        SeasonContext.completedSessions(from: team.sessions ?? [], duringLastDays: 7)
    }

    var weeklyKm: Double {
        SeasonContext.loadKilometers(from: weeklySessions)
    }

    var seasonalKm: Double {
        SeasonContext.loadKilometers(from: seasonalSessions)
    }

    var seasonalZoneBreakdown: [(zone: TrainingZone, km: Double)] {
        let zones: [TrainingZone] = [.ga1, .ga2, .e1, .e2, .anMix, .alactic]
        let blocks = seasonalSessions
            .flatMap { $0.sessionBlocks ?? [] }
            .filter { $0.trainingZone != .recovery }

        return zones.map { zone in
            let km = blocks
                .filter { $0.trainingZone == zone }
                .compactMap { distanceKm(for: $0) }
                .reduce(0, +)
            return (zone, km)
        }
    }

    var body: some View {
        List {
            Section {
                StatStrip(items: [
                    StatStripItem(value: "\(activeMembers.count)", label: "Athletes", color: .accentColor),
                    StatStripItem(value: "\((team.sessions ?? []).filter { $0.status == .completed }.count)",
                             label: "Practices", color: .green),
                    StatStripItem(value: team.createdAt.formatted(.dateTime.month(.abbreviated).year()),
                             label: "Created", color: .secondary, valueFont: .subheadline)
                ])
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                TeamTrainingLoadCard(
                    weeklyKm: weeklyKm,
                    seasonalKm: seasonalKm,
                    zoneBreakdown: seasonalZoneBreakdown
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section {
                if activeMembers.isEmpty {
                    Text("No athletes yet — tap + to add")
                        .font(.subheadline)
                        .foregroundStyle(Color.readableSecondary)
                } else {
                    ForEach(activeMembers) { athlete in
                        NavigationLink(destination: AthleteProfileView(athlete: athlete)) {
                            AthleteRow(athlete: athlete)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                athleteToRemove = athlete
                            } label: {
                                Label("Remove", systemImage: "person.badge.minus")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                athleteToRemove = athlete
                            } label: {
                                Label("Remove", systemImage: "person.badge.minus")
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Roster")
                    Spacer()
                    Button {
                        showingAddMember = true
                    } label: {
                        Label("Add Athlete", systemImage: "person.badge.plus")
                            .font(.caption).fontWeight(.semibold)
                            .comfortableTapTarget()
                    }
                }
            }

            if let desc = team.teamDescription, !desc.isEmpty {
                Section("Notes") {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(Color.readableSecondary)
                }
            }

            Section {
                Button {
                    team.isArchived.toggle()
                    do {
                        try SyncStore.save(modelContext)
                    } catch {
                        saveErrorMessage = error.localizedDescription
                        showSaveError = true
                    }
                } label: {
                    Label(
                        team.isArchived ? "Unarchive Team" : "Archive Team",
                        systemImage: team.isArchived ? "tray.and.arrow.up" : "archivebox"
                    )
                    .foregroundStyle(team.isArchived ? .blue : .orange)
                }
            }
        }
#if os(iOS)
        .listStyle(.insetGrouped)
#else
        .listStyle(.inset)
#endif
        .navigationTitle(team.teamName)
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Edit") { showingEditTeam = true }
            }
        }
        .sheet(isPresented: $showingAddMember) {
            AddMemberSheet(team: team, availableAthletes: availableAthletes)
#if os(macOS)
                .frame(minWidth: 520, minHeight: 600)
#endif
        }
        .sheet(isPresented: $showingEditTeam) {
            EditTeamSheet(team: team)
#if os(macOS)
                .frame(minWidth: 460, minHeight: 360)
#endif
        }
        .alert("Save Error", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
        .confirmationDialog(
            "Remove \(athleteToRemove?.fullName ?? "athlete") from \(team.teamName)?",
            isPresented: Binding(get: { athleteToRemove != nil },
                                 set: { if !$0 { athleteToRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove from Team", role: .destructive) {
                if let athlete = athleteToRemove { removeAthlete(athlete) }
                athleteToRemove = nil
            }
            Button("Cancel", role: .cancel) { athleteToRemove = nil }
        }
    }

    /// Ends the athlete's active membership instead of deleting historical team data.
    private func removeAthlete(_ athlete: Athlete) {
        if let membership = (team.memberships ?? []).first(where: {
            $0.athlete?.id == athlete.id && $0.leftDate == nil
        }) {
            membership.leftDate = Date()
            do {
                try SyncStore.save(modelContext)
            } catch {
                saveErrorMessage = error.localizedDescription
                showSaveError = true
            }
        }
    }

    private func distanceKm(for block: SessionBlock) -> Double? {
        block.effectiveDistanceKm
    }
}

/// Summarizes recent and seasonal training load for a team.
struct TeamTrainingLoadCard: View {
    let weeklyKm: Double
    let seasonalKm: Double
    let zoneBreakdown: [(zone: TrainingZone, km: Double)]

    private func loadStat(_ km: Double, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: "%.1f", km))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.readableSecondary)
        }
        .fixedSize()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Training Load")

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    loadStat(weeklyKm, label: "km last 7 days", color: .accentColor)
                    loadStat(seasonalKm, label: "km this season", color: .readableGreen)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 12) {
                    loadStat(weeklyKm, label: "km last 7 days", color: .accentColor)
                    loadStat(seasonalKm, label: "km this season", color: .readableGreen)
                }
            }

            Text("Seasonal km by zone")
                .font(.caption)
                .foregroundStyle(Color.readableSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(zoneBreakdown, id: \.zone) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.zone.rawValue)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(item.zone.color)
                            Text(item.zone.description)
                                .font(.caption2)
                                .foregroundStyle(Color.readableSecondary)
                                .lineLimit(2)
                            Text(String(format: "%.1f km", item.km))
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(item.zone.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(item.zone.rawValue), \(item.zone.description)")
                    }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Add Team Sheet

/// Creates a new team record.
struct AddTeamSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var teamName = ""
    @State private var description = ""
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    var isValid: Bool {
        !teamName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Team Info") {
                    TextField("Team Name (e.g. Sprint A Squad)", text: $teamName)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Team")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createTeam() }
                        .disabled(!isValid)
                        .fontWeight(.semibold)
                }
            }
            .alert("Save Error", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
#if os(iOS)
        .presentationDragIndicator(.visible)
#endif
    }

    /// Persists a new team.
    private func createTeam() {
        let team = Team(
            teamName: teamName.trimmingCharacters(in: .whitespaces),
            description: description.isEmpty ? nil : description
        )
        modelContext.insert(team)
        do {
            try SyncStore.save(modelContext)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }
}

// MARK: - Add Member Sheet

/// Adds active athletes to a team by creating membership records.
struct AddMemberSheet: View {
    let team: Team
    let availableAthletes: [Athlete]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    var filtered: [Athlete] {
        if searchText.isEmpty { return availableAthletes }
        return availableAthletes.filter {
            $0.fullName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var groupedByCategory: [(category: String, athletes: [Athlete])] {
        let grouped = Dictionary(grouping: filtered) { $0.ageCategory }
        return SeasonContext.ageCategoryDisplayOrder.compactMap { cat in
            guard let group = grouped[cat], !group.isEmpty else { return nil }
            return (category: cat, athletes: group)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if availableAthletes.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "person.slash")
                            .font(.largeTitle)
                            .foregroundStyle(Color.readableSecondary)
                        Text("All active athletes are already on this team")
                            .font(.subheadline)
                            .foregroundStyle(Color.readableSecondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding()
                } else {
                    List {
                        ForEach(groupedByCategory, id: \.category) { group in
                            Section {
                                ForEach(group.athletes) { athlete in
                                    Button {
                                        addAthlete(athlete)
                                    } label: {
                                        AthleteRow(athlete: athlete)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                CategoryHeader(category: group.category,
                                               count: group.athletes.count)
                            }
                        }
                    }
#if os(iOS)
                    .listStyle(.insetGrouped)
#else
                    .listStyle(.inset)
#endif
                    .searchable(text: $searchText, prompt: "Search athletes")
                }
            }
            .navigationTitle("Add to \(team.teamName)")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Save Error", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
    }

    private func addAthlete(_ athlete: Athlete) {
        let membership = TeamMembership(athlete: athlete, team: team)
        modelContext.insert(membership)
        do {
            try SyncStore.save(modelContext)
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }
}

// MARK: - Edit Team Sheet

/// Edits the name and description of an existing team.
struct EditTeamSheet: View {
    @Bindable var team: Team
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var description: String
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    init(team: Team) {
        self.team = team
        _name = State(initialValue: team.teamName)
        _description = State(initialValue: team.teamDescription ?? "")
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Team Info") {
                    TextField("Team Name", text: $name)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Team")
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
            .alert("Save Error", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
#if os(iOS)
        .presentationDragIndicator(.visible)
#endif
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let trimmedDesc = description.trimmingCharacters(in: .whitespaces)
        team.teamName = trimmed
        team.teamDescription = trimmedDesc.isEmpty ? nil : trimmedDesc
        do {
            try SyncStore.save(modelContext)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }
}
