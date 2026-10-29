/// Shared SwiftData container setup for the iOS and macOS targets.
///
/// Both `CoachSyncApp` and `CoachSyncMacApp` build their `ModelContainer`
/// through `CoachSyncContainer.make()`, so the schema and the launch/recovery
/// logic live in exactly one place — there is no per-platform copy to drift.
///
/// As of Phase 2 Stage 3a the store is **local-only** (`cloudKitDatabase: .none`).
/// CloudKit sync was retired in favor of the CoachSync backend — the single sync
/// hub, and the only path that shares a club across separate Apple IDs.

import SwiftUI
import SwiftData

/// Whether this process was launched by the XCUITest harness.
///
/// Gated to `#if DEBUG` deliberately, and consulted by three places that must never touch a
/// coach's real data or the live backend during a test run: the container swap
/// (`CoachSyncContainer.make()`), the Keychain session restore (`CoachSyncApp`), and the sync
/// chokepoint (`SyncCoordinator.syncNow()`). Release builds always report `false`, so a shipped
/// app can't be dropped into the seeded in-memory store via `open CoachSync.app --args UI_TESTING`.
///
/// `nonisolated` (the module defaults to MainActor isolation): reading `ProcessInfo` is pure and
/// thread-safe, and this is consulted from nonisolated contexts.
nonisolated enum AppEnvironment {
    static var isUITesting: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("UI_TESTING")
#else
        false
#endif
    }
}

enum CoachSyncContainer {

    /// Result of attempting to build the model container at launch.
    struct LaunchState {
        let container: ModelContainer
        let launchErrorMessage: String?
    }

    /// Every `@Model` type in the app. Must stay in sync with `Models.swift`.
    static let schema = Schema([
        Athlete.self,
        Team.self,
        TeamMembership.self,
        CoachSession.self,
        SessionBlock.self,
        AttendanceRecord.self,
        PerformanceRecord.self,
        AthleteNote.self,
        FitnessTestResult.self,
        RegattaResult.self,
        SeasonArchive.self,
        TechnicalAssessment.self,
        TechnicalRating.self,
        DevelopmentNote.self,
        HeightRecord.self,
        KTCAssessment.self,
        Coach.self,
        PendingChange.self   // local-only sync outbox (never leaves the device)
    ])

    /// Message shown by `StoreRecoveryView` when the persistent store can't open.
    private static let recoveryMessage = """
    CoachSync couldn't open the local data store, so the app started in temporary recovery mode to protect your saved data.

    Existing on-device data was not deleted. The stored file may need migration or manual recovery before normal launch can resume.
    """

    /// Fixed coach id seeded when launched under UI testing (`-currentCoachID`
    /// in the test's launch arguments matches this), so XCUITests can skip the
    /// onboarding flow deterministically instead of exercising it every run.
    static let uiTestCoachID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// Builds the persistent local container. A transient failure is retried once;
    /// a persistent failure (or an unavailable store directory) falls back to a
    /// temporary in-memory store so the app can present recovery UI instead of
    /// crashing.
    static func make() -> LaunchState {
        if AppEnvironment.isUITesting {
            return makeUITestingContainer()
        }

        guard let storeURL = storeURL() else {
            return inMemoryFallback(reason: "app support directory unavailable")
        }

        let config = ModelConfiguration(
            "CoachSync",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        for attempt in 1...2 {
            do {
                let container = try ModelContainer(for: schema, configurations: config)
                // The app commits exclusively through the explicit `SyncStore.save` chokepoint
                // (every mutating view calls it, never a bare `modelContext.save()`) so the outbox
                // and `updatedAt` stamping stay in lockstep with what's actually persisted. SwiftData's
                // default autosave would let a live-bound edit (e.g. `@Bindable` fields in
                // EditSessionSheet) commit on its own — on scene backgrounding, for instance — bypassing
                // that chokepoint entirely and leaving the sync engine unaware the edit ever happened.
                container.mainContext.autosaveEnabled = false
                return LaunchState(container: container, launchErrorMessage: nil)
            } catch {
                print("CoachSync: store open attempt \(attempt) of 2 failed — \(error)")
            }
        }

        return inMemoryFallback(reason: "persistent store could not be opened")
    }

    /// Fixed id of the athlete seeded for UI testing (see `makeUITestingContainer`)
    /// so a session-logging test always has exactly one athlete to mark
    /// attendance for.
    static let uiTestAthleteID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    /// Fixed club id carried by `uiTestSession` — never a real backend club, just something
    /// non-nil so `OnboardingGate`'s club-approval check (multi-club tenancy slice 5) is satisfied.
    static let uiTestClubID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    /// A fake, already-approved backend session for UI testing, seeded into an in-memory
    /// `TokenStoring` (see `CoachSyncApp`/`CoachSyncMacApp` `init()`) — never the real Keychain,
    /// never a real backend token. Its coach id matches `uiTestCoachID` so this session and the
    /// local `Coach` row `makeUITestingContainer` seeds refer to the same identity, exactly like a
    /// real signed-in-and-synced coach's local row would.
    static var uiTestSession: StoredSession {
        StoredSession(
            token: "ui-testing-fake-token",
            expiresAt: Date().addingTimeInterval(60 * 60 * 24 * 30),
            coach: CoachDTO(id: uiTestCoachID, name: "UI Test Coach", role: nil, nccpLevel: nil,
                            colorHex: nil, createdAt: Date(), updatedAt: Date()),
            clubId: uiTestClubID)
    }

    /// In-memory container for UI tests, pre-seeded with a fixed-id coach so
    /// `OnboardingGate` is already satisfied once the test passes
    /// `-currentCoachID` matching `uiTestCoachID` as a launch argument AND the
    /// app's `init()` has seeded `uiTestSession` into an in-memory `AuthManager`
    /// (multi-club tenancy slice 5 made the gate also require an approved
    /// backend club, not just a locally selected coach), plus one fixed-id
    /// athlete so attendance/session-logging tests have a roster.
    private static func makeUITestingContainer() -> LaunchState {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(for: schema, configurations: config)
            container.mainContext.autosaveEnabled = false
            let coach = Coach(name: "UI Test Coach")
            coach.id = uiTestCoachID
            container.mainContext.insert(coach)
            // Deliberately NOT named "Test Athlete" — AthleteCRUDUITests creates
            // and asserts on an athlete with that exact name, and a same-named
            // seed row would make that assertion trivially pass even if broken.
            let athlete = Athlete(firstName: "Roster", lastName: "Seed",
                                  dateOfBirth: SeasonContext.defaultNewAthleteDateOfBirth())
            athlete.id = uiTestAthleteID
            container.mainContext.insert(athlete)
            try container.mainContext.save()
            return LaunchState(container: container, launchErrorMessage: nil)
        } catch {
            fatalError("CoachSync: failed to create UI testing ModelContainer — \(error)")
        }
    }

    /// Last-resort in-memory container so the recovery screen can be shown
    /// instead of the app crashing on launch.
    private static func inMemoryFallback(reason: String) -> LaunchState {
        print("CoachSync: starting in recovery mode — \(reason)")
        let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(for: schema, configurations: fallbackConfig)
            return LaunchState(container: container, launchErrorMessage: recoveryMessage)
        } catch {
            fatalError("CoachSync: failed to create an in-memory ModelContainer — \(error)")
        }
    }

    /// URL of the persistent SQLite store, creating its directory if needed.
    /// Returns `nil` (rather than crashing) when the directory can't be prepared.
    ///
    /// Uses a fresh `CoachSyncLocal.store` filename — distinct from the retired
    /// CloudKit-mirrored `CoachSync.store` — so the Stage-3a cutover opens a clean
    /// local store instead of reopening a former-CloudKit file. Per the "start
    /// fresh" decision, data in the old store is intentionally not migrated.
    static func storeURL() -> URL? {
        let directory = URL.applicationSupportDirectory
            .appending(path: "CoachSync", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print("CoachSync: failed to prepare app support directory — \(error)")
            return nil
        }
        return directory.appending(path: "CoachSyncLocal.store")
    }
}

/// Shown at launch when the persistent store could not be opened. Lets the
/// coach delete the local store and restart as a last resort.
struct StoreRecoveryView: View {
    let message: String
    @State private var showingDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Data Store Unavailable",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text(message)
            )
            .padding()
            .navigationTitle("CoachSync")
            .safeAreaInset(edge: .bottom) {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete Store and Start Fresh", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding()
            }
            .alert("Delete All Data?", isPresented: $showingDeleteConfirm) {
                Button("Delete and Restart", role: .destructive) { deleteStoreAndExit() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes the local data store and exits the app. CoachSync will start fresh on next launch.")
            }
        }
    }

    /// Removes the store file and its SQLite companion files, then terminates
    /// so a clean relaunch creates a fresh store.
    private func deleteStoreAndExit() {
        if let storeURL = CoachSyncContainer.storeURL() {
            let fm = FileManager.default
            for suffix in ["", "-wal", "-shm"] {
                let url = storeURL.deletingLastPathComponent()
                    .appending(path: storeURL.lastPathComponent + suffix)
                try? fm.removeItem(at: url)
            }
        }
        exit(0)
    }
}
