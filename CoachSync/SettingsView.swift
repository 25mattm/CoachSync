/// Collects app-level settings, import tools, and destructive data actions.

import SwiftUI
import SwiftData

/// Settings hub for configuration and maintenance tasks.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var auth
    @Environment(SyncCoordinator.self) private var sync
    @Query(filter: #Predicate<Athlete> { $0.isActive }) private var activeAthletes: [Athlete]
    @Query(filter: #Predicate<Athlete> { !$0.isActive }) private var inactiveAthletes: [Athlete]
    @Query(filter: #Predicate<Team> { !$0.isArchived }) private var activeTeams: [Team]
    @Query(filter: #Predicate<Team> { $0.isArchived }) private var archivedTeams: [Team]
    @Query(filter: #Predicate<CoachSession> { !$0.isArchived }) private var activeSessions: [CoachSession]
    @Query(filter: #Predicate<CoachSession> { $0.isArchived }) private var archivedSessions: [CoachSession]
    @Query(sort: \SeasonArchive.archiveDate, order: .reverse) private var seasonArchives: [SeasonArchive]
    @Query(sort: \Coach.createdAt) private var coaches: [Coach]
    @Query private var pendingChanges: [PendingChange]

    @AppStorage(CoachIdentity.idKey) private var currentCoachID = ""
    @AppStorage(CoachIdentity.nameKey) private var currentCoachName = ""
    @State private var editingCoach: Coach?
    @State private var showingAddCoach = false

    @State private var clubName: String = UserDefaults.standard.string(forKey: "clubName") ?? ""
    @State private var showingClearDataAlert = false
    @State private var showingResetSessionDataAlert = false
    @State private var showingImport = false
    @State private var showingArchiveSeasonAlert = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showingUnsyncedSignOutAlert = false

    /// Completed but not-yet-archived practices — the archive action's input.
    var completedSessions: [CoachSession] { activeSessions.filter { $0.status == .completed } }

    /// Completed practices across active AND archived. Stats use this so
    /// archiving (which only hides sessions from Dashboard/Schedule) doesn't
    /// make the season figures read as zero while Team detail still counts
    /// the same sessions.
    var allCompletedSessions: [CoachSession] {
        (activeSessions + archivedSessions).filter { $0.status == .completed }
    }

    var currentSeasonYear: Int {
        SeasonContext.currentYear()
    }

    var currentSeasonCompletedSessions: [CoachSession] {
        SeasonContext.completedSessions(from: activeSessions + archivedSessions, inYear: currentSeasonYear)
    }

    var currentSeasonKm: Double {
        SeasonContext.loadKilometers(from: currentSeasonCompletedSessions)
    }

    /// Reference rows derived from the current season year so the help text stays current.
    var ageCategoryReferenceRows: [(category: String, rule: String)] {
        SeasonContext.ageCategoryReferenceRows(forYear: currentSeasonYear)
    }

    /// Backend club sync: Sign in with Apple, then push local changes + pull everyone else's
    /// through the backend (the cross-Apple-ID sharing path).
    @ViewBuilder private var clubSyncSection: some View {
        Section {
            if let session = auth.currentSession {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.coach.name)
                        Text("Signed in to the club backend")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button {
                    Task { await sync.syncNow() }
                } label: {
                    HStack {
                        Text("Sync Now")
                        if sync.status == .syncing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(sync.status == .syncing)
                syncStatusLabel
                Button("Sign Out", role: .destructive) { signOutTapped() }
            } else {
                SignInWithAppleButtonView()
                if let error = auth.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        } header: {
            Text("Club Sync")
        } footer: {
            Text("Sign in with Apple to share this club's athletes, sessions, and notes with other "
                 + "coaches' devices through the backend. \"Sync Now\" pushes your changes and pulls "
                 + "everyone else's; the app also syncs on launch and after you make changes.")
        }
    }

    @ViewBuilder private var syncStatusLabel: some View {
        switch sync.status {
        case .success(let date, let stuckCount) where stuckCount > 0:
            VStack(alignment: .leading, spacing: 2) {
                Text("Last synced \(date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                Text(stuckCount == 1
                     ? "1 change couldn't sync — check for invalid data (e.g. an email field) and try again."
                     : "\(String(stuckCount)) changes couldn't sync — check for invalid data (e.g. an email field) and try again.")
                    .font(.caption).foregroundStyle(.orange)
            }
        case .success(let date, _):
            Text("Last synced \(date.formatted(date: .omitted, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red)
        case .needsReauth:
            Text("Your session expired — sign out and sign in again.")
                .font(.caption).foregroundStyle(.red)
        case .idle, .syncing:
            EmptyView()
        }
    }

    var body: some View {
        NavigationStack {
            Form {

                clubSyncSection

                Section {
                    HStack {
                        Image(systemName: "building.2")
                            .foregroundStyle(Color.accentColor)
                        TextField("Club Name", text: $clubName)
                            .onChange(of: clubName) { _, new in
                                UserDefaults.standard.set(new, forKey: "clubName")
                            }
                    }
                } header: {
                    Text("Club Info")
                } footer: {
                    Text("Displayed throughout the app.")
                }

                Section {
                    if !coaches.isEmpty {
                        Picker("This device is", selection: $currentCoachID) {
                            ForEach(coaches) { coach in
                                Text(coach.name).tag(coach.id.uuidString)
                            }
                        }
                        .onChange(of: currentCoachID) { _, newID in
                            if let coach = coaches.first(where: { $0.id.uuidString == newID }) {
                                currentCoachName = coach.name
                            }
                        }
                    }

                    ForEach(coaches) { coach in
                        Button {
                            editingCoach = coach
                        } label: {
                            HStack(spacing: 12) {
                                CoachAvatarChip(initials: coach.initials, color: coach.displayColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(coach.name).foregroundStyle(.primary)
                                    let detail = [coach.role, coach.nccpLevel]
                                        .compactMap { $0 }
                                        .filter { !$0.isEmpty }
                                        .joined(separator: " · ")
                                    if !detail.isEmpty {
                                        Text(detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        showingAddCoach = true
                    } label: {
                        Label("Add Coach", systemImage: "person.badge.plus")
                            .foregroundStyle(Color.accentColor)
                    }
                } header: {
                    Text("Coaches")
                } footer: {
                    Text("“This device is” sets which coach the sessions and notes you log on this device are credited to. Coaches share the club’s data through the club server, not iCloud.")
                }

                Section("Overview") {
                    StatRow(label: "Athletes", value: "\(activeAthletes.count)",
                            icon: "person.2.fill", color: .blue)
                    StatRow(label: "Teams", value: "\(activeTeams.count)",
                            icon: "person.3.fill", color: .green)
                    StatRow(label: "Practices Completed", value: "\(allCompletedSessions.count)",
                            icon: "checkmark.circle.fill", color: .orange)
                }

                Section("Age Category Reference (\(String(currentSeasonYear)) Season)") {
                    ForEach(ageCategoryReferenceRows, id: \.category) { item in
                        AgeCategoryRow(category: item.category, rule: item.rule)
                    }
                }

                Section {
                    Button {
                        showingImport = true
                    } label: {
                        Label("Import Athletes from CSV", systemImage: "square.and.arrow.down")
                            .foregroundStyle(Color.accentColor)
                    }
                } header: {
                    Text("Import")
                } footer: {
                    Text("Import athletes from a spreadsheet exported as CSV. Duplicates are skipped automatically.")
                }

                Section {
                    HStack {
                        Text("Current Season")
                        Spacer()
                        // String() — Int interpolation in Text applies locale
                        // grouping and renders the year as "2,026".
                        Text(String(currentSeasonYear))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Completed Practices")
                        Spacer()
                        Text("\(currentSeasonCompletedSessions.count)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Total Km Logged")
                        Spacer()
                        Text(String(format: "%.1f km", currentSeasonKm))
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showingArchiveSeasonAlert = true
                    } label: {
                        Label("Archive Completed Practices", systemImage: "archivebox.fill")
                            .foregroundStyle(.orange)
                    }
                    .disabled(completedSessions.isEmpty)
                } header: {
                    Text("Season Management")
                } footer: {
                    Text("Archiving removes completed practices from active Dashboard and Schedule views while preserving all athlete performance history and trend data.")
                }

                if !seasonArchives.isEmpty {
                    Section {
                        ForEach(seasonArchives) { archive in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(String(archive.seasonYear))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(archive.archiveDate.formatted(.dateTime.month(.abbreviated).day().year()))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                HStack(spacing: 12) {
                                    Text("\(archive.totalSessions) practice\(archive.totalSessions == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(String(format: "%.1f km", archive.totalKm))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(archive.totalAthletes) athletes")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Archived Practices")
                    }
                }

                Section {
                    Button {
                        showingResetSessionDataAlert = true
                    } label: {
                        Label("Reset Session Data", systemImage: "trash")
                            .foregroundStyle(.orange)
                    }

                    Button {
                        showingClearDataAlert = true
                    } label: {
                        Label("Reset All Data", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Data Management")
                } footer: {
                    Text("These clear this device only — they never delete anything from your club, and data already synced to the club downloads again on the next sync. Reset Session Data clears practices, blocks, and performance records while keeping athletes, teams, assessments, and development journal entries. Reset All Data clears everything.")
                }

                Section("About") {
                    HStack {
                        Text("App")
                        Spacer()
                        Text("CoachSync")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Built for")
                        Spacer()
                        Text("Paddling coaches")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .sheet(isPresented: $showingImport) {
                CSVImportView()
#if os(macOS)
                    .frame(minWidth: 500, minHeight: 600)
#endif
            }
            .sheet(isPresented: $showingAddCoach) {
                CoachEditSheet(coach: nil)
            }
            .sheet(item: $editingCoach) { coach in
                CoachEditSheet(coach: coach)
            }
            .alert("Reset Session Data?", isPresented: $showingResetSessionDataAlert) {
                Button("Reset Session Data", role: .destructive) { clearSessions() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears all practices, workout blocks, performance records, attendance records, and session notes from this device. Athlete profiles, teams, technical assessments, development journal entries, and regatta results will be preserved. Other coaches are not affected, and practices already synced to your club download again on the next sync. Unsynced practice changes on this device are lost.")
            }
            .alert("Reset All Data?", isPresented: $showingClearDataAlert) {
                Button("Reset Everything", role: .destructive) { resetAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears all athletes, teams, practices, and performance data from this device. Other coaches are not affected, and data already synced to your club downloads again on the next sync. Unsynced changes on this device are lost.")
            }
            .alert("Archive Completed Practices?", isPresented: $showingArchiveSeasonAlert) {
                Button("Archive", role: .destructive) { archiveCompletedSessions() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Archiving will mark all completed practices as archived and remove them from active Dashboard and Schedule views. Practices from earlier seasons are archived under their own season. Athlete performance data and trend calculations are preserved permanently.")
            }
            .alert("Save Error", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
            .alert("Unsynced Changes", isPresented: $showingUnsyncedSignOutAlert) {
                Button("Sign Out Anyway", role: .destructive) { auth.signOut() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You have \(pendingChanges.count) change(s) that haven't synced to the backend yet. "
                     + "If a different coach signs in on this device before those changes sync, they'll be "
                     + "pushed under that coach's name. Tap \"Sync Now\" first, or sign out anyway.")
            }
        }
    }

    /// Guards against the sign-out-before-sync misattribution gap: a coach's still-pending offline
    /// edits, pushed after a different coach signs in on the same device, would otherwise be
    /// attributed to whoever is signed in when the outbox finally drains.
    private func signOutTapped() {
        if pendingChanges.isEmpty {
            auth.signOut()
        } else {
            showingUnsyncedSignOutAlert = true
        }
    }

    // MARK: - Data Management

    /// Removes all session data from this device while leaving athletes and teams intact.
    /// Device-local by design: deleting through `SyncStore.save` would queue a DELETE per record
    /// and wipe the shared club for every coach on the next sync.
    private func clearSessions() {
        do {
            try LocalWipe.wipeSessions(in: modelContext)
        } catch {
            saveErrorMessage = error.localizedDescription
            showingSaveError = true
        }
    }

    /// Clears all app data from this device, including coach profiles and this device's coach
    /// identity (so onboarding re-runs and a handed-off device stops stamping the previous coach's
    /// name). Device-local for the same reason as `clearSessions` — never pushes deletes to the club.
    private func resetAllData() {
        do {
            try LocalWipe.wipeAll(in: modelContext)
            currentCoachID = ""
            currentCoachName = ""
        } catch {
            saveErrorMessage = error.localizedDescription
            showingSaveError = true
        }
    }

    /// Archives every completed, not-yet-archived practice, grouped into one
    /// `SeasonArchive` snapshot per season year — so leftovers from a season
    /// the coach forgot to archive before Jan 1 still get stamped under their
    /// own year instead of becoming permanently unarchivable.
    private func archiveCompletedSessions() {
        let sessionsToArchive = completedSessions
        guard !sessionsToArchive.isEmpty else { return }

        let byYear = Dictionary(grouping: sessionsToArchive) {
            SeasonContext.year(of: $0.scheduledDate)
        }
        for (year, sessions) in byYear {
            let uniqueAthletes = Set(
                sessions
                    .flatMap { $0.attendanceRecords ?? [] }
                    .filter { $0.status == .present }
                    .compactMap { $0.athlete?.id }
            )
            let archive = SeasonArchive(
                seasonYear: year,
                totalAthletes: uniqueAthletes.count,
                totalSessions: sessions.count,
                totalKm: SeasonContext.loadKilometers(from: sessions)
            )
            modelContext.insert(archive)
            sessions.forEach { $0.isArchived = true }
        }
        saveContext()
    }

    /// Saves the shared model context and surfaces any persistence error.
    private func saveContext() {
        do {
            try SyncStore.save(modelContext)
        } catch {
            saveErrorMessage = error.localizedDescription
            showingSaveError = true
        }
    }
}

// MARK: - Stat Row

/// Reusable settings row for a labeled stat with icon and accent color.
struct StatRow: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Age Category Row

/// Reference row for the static age-category help section.
struct AgeCategoryRow: View {
    let category: String
    let rule: String

    var body: some View {
        HStack {
            CategoryPill(category: category)
            Spacer()
            Text(rule)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Coach Edit Sheet

/// Create or edit a coach profile. Passing `coach: nil` creates a new one.
struct CoachEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let coach: Coach?

    @State private var name = ""
    @State private var role = ""
    @State private var nccpLevel = ""   // "" = none
    @State private var confirmingDelete = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    /// True when editing the coach this device stamps onto new records.
    /// Deleting them would bounce this device straight back into onboarding,
    /// so the delete affordance is disabled until another coach is selected.
    private var isActiveCoach: Bool {
        coach.map { CoachIdentity.currentID == $0.id.uuidString } ?? false
    }

    var body: some View {
        NavigationStack {
            Form {
                CoachFormFields(name: $name, role: $role, nccpLevel: $nccpLevel)

                if coach != nil {
                    Section {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label("Delete Coach", systemImage: "trash")
                        }
                        .disabled(isActiveCoach)
                    } footer: {
                        if isActiveCoach {
                            Text("This is the active coach on this device — switch “This device is” in Settings first.")
                        } else {
                            Text("Their name stays on the practices and notes they already logged.")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(coach == nil ? "New Coach" : "Edit Coach")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear(perform: load)
            .confirmationDialog(
                "Delete \(coach?.name ?? "coach")?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Coach", role: .destructive) { deleteCoach() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Their name remains on practices and notes they logged. A device still using this profile will be asked to pick a coach again.")
            }
            .alert("Couldn't Delete Coach", isPresented: $showDeleteError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(deleteErrorMessage)
            }
            .alert("Couldn't Save Coach", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
#if os(macOS)
            .frame(minWidth: 420, minHeight: 320)
#endif
        }
    }

    private func load() {
        guard let coach else { return }
        name = coach.name
        role = coach.role ?? ""
        nccpLevel = coach.nccpLevel ?? ""
    }

    private func save() {
        let trimmedRole = role.trimmingCharacters(in: .whitespaces)
        if let coach {
            coach.name = trimmedName
            coach.role = trimmedRole.isEmpty ? nil : trimmedRole
            coach.nccpLevel = nccpLevel.isEmpty ? nil : nccpLevel
        } else {
            let new = Coach(
                name: trimmedName,
                role: trimmedRole.isEmpty ? nil : trimmedRole,
                nccpLevel: nccpLevel.isEmpty ? nil : nccpLevel
            )
            modelContext.insert(new)
        }
        do {
            try SyncStore.save(modelContext)
        } catch {
            // Undo the in-memory edit/insert; the form keeps the typed values for a retry.
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
            showSaveError = true
            return
        }
        // Keep the device's current-coach name snapshot in sync when editing
        // the active coach, so future "logged by" tags use the new name.
        if let coach, CoachIdentity.currentID == coach.id.uuidString {
            CoachIdentity.setCurrent(coach)
        }
        dismiss()
    }

    /// Deletes the coach profile. Coach is a leaf model (no child
    /// relationships), so a plain delete is correct — see
    /// `ModelContext+Cascades.swift`. Attribution survives because
    /// `createdByCoachName` stamps are name snapshots, not relationships.
    private func deleteCoach() {
        guard let coach, !isActiveCoach else { return }
        modelContext.delete(coach)
        do {
            try SyncStore.save(modelContext)
            dismiss()
        } catch {
            deleteErrorMessage = error.localizedDescription
            showDeleteError = true
        }
    }
}
