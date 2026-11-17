/// First-launch onboarding: sign in with Apple, join a club (or wait for approval), set up the club
/// display name, and create (or pick) a coach profile. Also hosts the small shared helpers for "who
/// is this device's coach" and the coach avatar chip used for attribution.

import SwiftUI
import SwiftData

// MARK: - Current coach identity (device-local)

/// Tracks which coach profile is active on this device. Stored in `UserDefaults`
/// so it stays device-local (it is NOT synced — each device picks its own coach),
/// alongside a name snapshot used to stamp "logged by" attribution cheaply.
enum CoachIdentity {
    static let idKey = "currentCoachID"
    static let nameKey = "currentCoachName"

    /// Marks `coach` as this device's active coach.
    static func setCurrent(_ coach: Coach) {
        UserDefaults.standard.set(coach.id.uuidString, forKey: idKey)
        UserDefaults.standard.set(coach.name, forKey: nameKey)
    }

    static var currentID: String? { UserDefaults.standard.string(forKey: idKey) }

    /// Clears this device's active-coach identity. Used by `LocalWipe` when the signed-in
    /// coach's club changes or is revoked, so the coach re-confirms "who am I" via the roster
    /// picker instead of risking a stale id misattributing new records after the wipe.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: idKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
    }

    /// Cached name snapshot. Only a fallback for when the live store can't be
    /// read; `currentName(in:)` is the source of truth for attribution.
    private static var snapshotName: String? {
        let name = UserDefaults.standard.string(forKey: nameKey)
        return (name?.isEmpty == false) ? name : nil
    }

    /// The active coach's CURRENT name, resolved from the store by the stable
    /// coach ID so a rename on any device flows into new "logged by" stamps.
    /// Falls back to the cached snapshot if the coach can't be fetched.
    static func currentName(in context: ModelContext) -> String? {
        guard let idString = currentID, let uuid = UUID(uuidString: idString) else {
            return snapshotName
        }
        var descriptor = FetchDescriptor<Coach>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        if let name = try? context.fetch(descriptor).first?.name {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        return snapshotName
    }
}

// MARK: - Coach avatar chip

/// Small circular initials badge in the coach's color. Used in coach lists and
/// next to "logged by" attribution.
struct CoachAvatarChip: View {
    let initials: String
    let color: Color
    var size: CGFloat = 28
    @Environment(\.self) private var environment

    /// A coach can pick any color, so the initials switch to black on a light one.
    private var initialsColor: Color {
        let c = color.resolve(in: environment)
        let luminance = 0.2126 * c.linearRed + 0.7152 * c.linearGreen + 0.0722 * c.linearBlue
        return luminance > 0.18 ? .black : .white
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(initialsColor)
            .frame(width: size, height: size)
            .background(Circle().fill(color))
            .accessibilityHidden(true)   // Decorative: the coach's name is always beside it.
    }
}

// MARK: - "Logged by" attribution label

/// Inline "Logged by <name>" caption shown on sessions and notes. Renders
/// nothing when no coach name was recorded (e.g. legacy data).
struct LoggedByLabel: View {
    let coachName: String?

    var body: some View {
        if let name = coachName, !name.isEmpty {
            Label("Logged by \(name)", systemImage: "person.fill")
                .font(.caption2)
                .foregroundStyle(Color.readableSecondary)
        }
    }
}

// MARK: - Coach form fields

/// The Name / Role / NCCP-level fields shared by the onboarding create-coach
/// step and the Settings coach editor, so the two can't drift. Embed inside a
/// `Form`. `nccpLevel == ""` means "no certification selected".
struct CoachFormFields: View {
    @Binding var name: String
    @Binding var role: String
    @Binding var nccpLevel: String

    var body: some View {
        Section("Coach") {
            TextField("Name", text: $name)
            TextField("Role / Title (optional)", text: $role)
        }
        Section("Certification (optional)") {
            Picker("NCCP Level", selection: $nccpLevel) {
                Text("None").tag("")
                ForEach(nccpLevels, id: \.self) { Text($0).tag($0) }
            }
        }
    }
}

// MARK: - Onboarding gate

/// Shows first-launch setup until this device has a selected coach signed in and approved into a
/// backend club, then renders the wrapped app content. Derived from live state so a re-installed
/// or synced device behaves correctly.
struct OnboardingGate<Content: View>: View {
    @Environment(AuthManager.self) private var auth
    @Query private var coaches: [Coach]
    @AppStorage(CoachIdentity.idKey) private var currentCoachID = ""
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    /// Completion requires BOTH a backend-resolved club (multi-club tenancy — a signed-in coach
    /// with `clubId == nil` is still pending an operator's approval) AND a selected local coach.
    /// The free-text club name is collected during onboarding but deliberately NOT part of this
    /// condition — Settings live-writes it per keystroke, so requiring it would yank the whole app
    /// back into onboarding the moment a coach clears the field to retype it. This is a snapshot
    /// from the session's last sign-in, not re-verified live on every launch; a coach removed from
    /// their club after completing onboarding is caught by the sync layer's 401 handling, not here.
    private var isComplete: Bool {
        guard auth.currentSession?.clubId != nil else { return false }
        return coaches.contains { $0.id.uuidString == currentCoachID }
    }

    var body: some View {
        if isComplete {
            content()
        } else {
            OnboardingView()
        }
    }
}

// MARK: - Onboarding flow

/// First-launch flow: sign in with Apple, wait for club approval if needed, name the club, then
/// create or pick a coach. Sign-in-first (multi-club tenancy slice 5) so the coach step can see the
/// backend-synced roster — including the coach's own auto-provisioned backend row, which the sync
/// engine's natural-key-by-id matching means picking "myself" from that list is what actually binds
/// this device's local `Coach` row to the backend coach id (no separate binding step needed).
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var auth
    @Query(sort: \Coach.createdAt) private var coaches: [Coach]

    @AppStorage("clubName") private var clubName = ""
    @AppStorage(CoachIdentity.idKey) private var currentCoachID = ""
    @AppStorage(CoachIdentity.nameKey) private var currentCoachName = ""

    private enum Step { case signIn, awaitingApproval, club, coach }
    @State private var step: Step = .signIn

    @State private var clubDraft = ""
    @State private var creatingNew = false
    /// True once the backend sync has been given a chance to import an existing
    /// coach roster, so a fresh device doesn't default straight to profile
    /// creation (and create a duplicate) while the sync is still in flight.
    @State private var didWaitForCoachSync = false

    // New-coach fields
    @State private var name = ""
    @State private var role = ""
    @State private var nccpLevel = ""   // "" = none

    // Join-code submission (awaitingApproval step)
    @State private var joinCode = ""
    @State private var joinStatusMessage: String?
    @State private var isSubmittingJoinCode = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .signIn:           signInStep
                case .awaitingApproval: awaitingApprovalStep
                case .club:              clubStep
                case .coach:             coachStep
                }
            }
            // The sign-in step has its own "Welcome to CoachSync" heading; a second title there
            // repeated it and reserved large-title space that pushed the content down.
            .navigationTitle(step == .signIn ? "" : "Welcome")
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            clubDraft = clubName
            step = initialStep
        }
        .onChange(of: auth.state) { _, _ in advanceIfSignedIn() }
        .alert("Couldn't Create Profile", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
    }

    /// Where to start: a coach who's already signed in (e.g. relaunching mid-onboarding, or a
    /// previously-approved coach whose local coach selection was lost) skips straight past the
    /// screen they've already cleared.
    private var initialStep: Step {
        guard let session = auth.currentSession else { return .signIn }
        return session.clubId != nil ? .club : .awaitingApproval
    }

    /// Advances past `.signIn`/`.awaitingApproval` when `auth.state` changes to reflect a newly
    /// signed-in or newly approved coach — covers both the initial sign-in and a "check again"
    /// re-sign-in from the awaiting-approval screen. Never steps backward.
    private func advanceIfSignedIn() {
        guard let session = auth.currentSession, step == .signIn || step == .awaitingApproval else { return }
        step = session.clubId != nil ? .club : .awaitingApproval
    }

    // MARK: Step 0a — sign in

    private var signInStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.water.fitness")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
            Text("Welcome to CoachSync")
                .font(.title2).bold()
            Text("Sign in with Apple to join your club.")
                .font(.subheadline)
                .foregroundStyle(Color.readableSecondary)
                .multilineTextAlignment(.center)
            SignInWithAppleButtonView()
                .frame(maxWidth: 320)
            if let policy = BackendConfig.privacyPolicyURL {
                Link("Privacy Policy", destination: policy)
                    .font(.footnote)
                    .comfortableTapTarget()
            }
            if let error = auth.errorMessage {
                Text(error).font(.caption).foregroundStyle(Color.readableRed)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Step 0b — awaiting approval

    /// Shown once signed in but before an operator has approved this coach into a club. Submitting
    /// a join code only registers intent (`POST /api/clubs/join`) — it never grants access by
    /// itself. "Sign in with Apple" again is the way to check for approval: it re-runs the exchange
    /// and picks up a fresh `clubId` if one is now set, which `advanceIfSignedIn()` reacts to.
    private var awaitingApprovalStep: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "hourglass")
                        .font(.largeTitle)
                        .foregroundStyle(Color.accentColor)
                    Text("Waiting for Approval")
                        .font(.title2).bold()
                    if let name = auth.currentSession?.coach.name {
                        Text("Signed in as \(name).")
                            .font(.subheadline)
                            .foregroundStyle(Color.readableSecondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Join a Club") {
                TextField("Join Code", text: $joinCode)
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
                    .autocorrectionDisabled()
                Button {
                    submitJoinCode()
                } label: {
                    HStack {
                        Text("Submit")
                        if isSubmittingJoinCode {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(joinCode.trimmingCharacters(in: .whitespaces).isEmpty || isSubmittingJoinCode)
                if let joinStatusMessage {
                    Text(joinStatusMessage).font(.caption).foregroundStyle(Color.readableSecondary)
                }
            }

            Section {
                Text("Ask your club administrator for a join code. Once they approve you, sign in "
                     + "again below to continue.")
                    .font(.caption)
                    .foregroundStyle(Color.readableSecondary)
                SignInWithAppleButtonView()
                Button("Sign Out", role: .destructive) {
                    auth.signOut()
                    step = .signIn
                }
            }
        }
        .formStyle(.grouped)
    }

    private func submitJoinCode() {
        isSubmittingJoinCode = true
        joinStatusMessage = nil
        Task {
            let result = await auth.joinClub(code: joinCode.trimmingCharacters(in: .whitespaces))
            isSubmittingJoinCode = false
            switch result {
            case .success:
                joinStatusMessage = "Request sent — waiting for your club to approve you."
            case .alreadyPending:
                joinStatusMessage = "You're already registered with a club — sign in again to check your status."
            case .invalidCode:
                joinStatusMessage = "No club found with that code. Double-check and try again."
            case .failure(let message):
                joinStatusMessage = message
            }
        }
    }

    // MARK: Step 1 — club

    private var clubStep: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "figure.water.fitness")
                        .font(.largeTitle)
                        .foregroundStyle(Color.accentColor)
                    Text("Set up your club")
                        .font(.title2).bold()
                    Text("This name appears throughout CoachSync. You can change it later in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(Color.readableSecondary)
                }
                .padding(.vertical, 4)
            }

            Section("Club") {
                TextField("Club Name", text: $clubDraft)
            }

            Section {
                Button {
                    clubName = clubDraft.trimmingCharacters(in: .whitespaces)
                    step = .coach
                } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(clubDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Step 2 — coach

    @ViewBuilder
    private var coachStep: some View {
        if creatingNew {
            // Explicit "create a new profile" choice always wins — this is the
            // escape hatch from the picker, so it must be checked before the
            // roster branch below (which would otherwise swallow it).
            createCoachForm
        } else if !coaches.isEmpty {
            // Roster present (locally or synced in) — let the coach pick.
            pickCoachList
        } else if didWaitForCoachSync {
            // Still no coaches after giving the backend sync a chance to import — create one.
            createCoachForm
        } else {
            // Brief settling window so a fresh device signing in to the club
            // doesn't create a duplicate while the roster is still importing.
            coachSyncWaitStep
        }
    }

    /// Shown only on the coach step before the roster has had a chance to sync.
    /// Auto-advances to profile creation so an offline/first-ever coach is never
    /// stuck, and offers a manual "set up now" escape.
    private var coachSyncWaitStep: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Checking for your club's coaches…")
                .font(.subheadline)
                .foregroundStyle(Color.readableSecondary)
            Button("Set up a new profile") { didWaitForCoachSync = true }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // ~3s is enough for a typical backend sync to deliver the roster;
            // if none arrives, fall through to creating a profile.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            didWaitForCoachSync = true
        }
    }

    private var createCoachForm: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Create your coach profile")
                        .font(.title2).bold()
                    Text("Your profile tags the sessions and notes you log so the club can see who recorded what.")
                        .font(.subheadline)
                        .foregroundStyle(Color.readableSecondary)
                }
                .padding(.vertical, 4)
            }

            CoachFormFields(name: $name, role: $role, nccpLevel: $nccpLevel)

            Section {
                Button {
                    createAndContinue()
                } label: {
                    Text("Get Started").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)

                if !coaches.isEmpty {
                    Button("Back") { creatingNew = false }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var pickCoachList: some View {
        Form {
            Section {
                Text("Who are you?")
                    .font(.title2).bold()
            }
            Section("Existing Coaches") {
                ForEach(coaches) { coach in
                    Button {
                        select(coach)
                    } label: {
                        HStack(spacing: 12) {
                            CoachAvatarChip(initials: coach.initials, color: coach.displayColor)
                            VStack(alignment: .leading) {
                                Text(coach.name).foregroundStyle(.primary)
                                if let role = coach.role, !role.isEmpty {
                                    Text(role).font(.caption).foregroundStyle(Color.readableSecondary)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
            Section {
                Button {
                    creatingNew = true
                } label: {
                    Label("Create a new profile", systemImage: "plus.circle")
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Actions

    private func createAndContinue() {
        let coach = Coach(
            name: name.trimmingCharacters(in: .whitespaces),
            role: role.trimmingCharacters(in: .whitespaces).isEmpty ? nil : role.trimmingCharacters(in: .whitespaces),
            nccpLevel: nccpLevel.isEmpty ? nil : nccpLevel
        )
        modelContext.insert(coach)
        do {
            try SyncStore.save(modelContext)
        } catch {
            // Selecting an unsaved coach would let onboarding finish with a profile that
            // vanishes on relaunch; discard it and keep the coach on this step to retry.
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
            showSaveError = true
            return
        }
        select(coach)
    }

    private func select(_ coach: Coach) {
        currentCoachID = coach.id.uuidString
        currentCoachName = coach.name
    }
}
