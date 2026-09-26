/// The iOS app entry point. SwiftData container setup lives in `SharedContainer.swift`.

import SwiftUI
import SwiftData
import Combine
import AuthenticationServices

@main
struct CoachSyncApp: App {

    let container: ModelContainer
    let launchErrorMessage: String?

    @Environment(\.scenePhase) private var scenePhase

    /// Owns the backend session (Sign in with Apple).
    @State private var auth: AuthManager
    /// Drives push-then-pull sync against the backend (Stage 3c).
    @State private var sync: SyncCoordinator

    /// Builds the persistent model container and the auth/sync owners used across the app.
    init() {
        let launchState = CoachSyncContainer.make()
        container = launchState.container
        launchErrorMessage = launchState.launchErrorMessage
        // Under UI testing, a fake already-approved session backed by an in-memory store — never
        // the real Keychain — so the seeded tests reach the main tab bar under the club-approval-
        // aware OnboardingGate without touching the developer's real signed-in identity or the live
        // backend (SyncCoordinator.syncNow() separately no-ops under UI testing regardless).
        let authManager = AppEnvironment.isUITesting
            ? AuthManager(store: InMemoryTokenStore(CoachSyncContainer.uiTestSession))
            : AuthManager()
        // Synchronous (a plain Keychain read, or the in-memory store above) — restoring here,
        // before the first render, means `OnboardingGate` sees an already-approved coach's session
        // on frame one instead of flashing onboarding while an async `.task` catches up.
        authManager.restore()
        _auth = State(initialValue: authManager)
        _sync = State(initialValue: SyncCoordinator(
            context: launchState.container.mainContext,
            tokenProvider: { authManager.currentSession?.token },
            clubIdProvider: { authManager.currentSession?.clubId }))
    }

    var body: some Scene {
        WindowGroup {
            if let launchErrorMessage {
                StoreRecoveryView(message: launchErrorMessage)
            } else {
                OnboardingGate { ContentView() }
                    .environment(auth)
                    .environment(sync)
                    .onChange(of: auth.state) { _, _ in
                        if auth.currentSession != nil { sync.requestSync() }   // sign-in / restore
                    }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active { sync.requestSync() }             // foreground
                    }
                    .onReceive(NotificationCenter.default.publisher(for: SyncStore.didSaveNotification)) { _ in
                        sync.requestSync()                                      // debounced after a local edit
                    }
                    .onReceive(NotificationCenter.default.publisher(
                        for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
                        // The coach revoked this app's Sign in with Apple grant (Settings ->
                        // Apple ID -> Sign in with Apple); the backend session is no longer
                        // meaningful, so end it immediately rather than waiting for the JWT's own
                        // (up to 30-day) expiry to force a re-auth on some later sync attempt.
                        auth.signOut()
                    }
            }
        }
        .modelContainer(container)
    }
}
