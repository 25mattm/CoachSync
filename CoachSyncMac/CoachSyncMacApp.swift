/// The macOS app entry point. SwiftData container setup lives in `SharedContainer.swift`.

import SwiftUI
import SwiftData
import Combine
import AuthenticationServices

@main
struct CoachSyncMacApp: App {

    let container: ModelContainer
    let launchErrorMessage: String?

    @Environment(\.scenePhase) private var scenePhase

    /// Owns the backend session (Sign in with Apple).
    @State private var auth: AuthManager
    /// Drives push-then-pull sync against the backend (Stage 3c).
    @State private var sync: SyncCoordinator

    /// Builds the persistent model container and the auth/sync owners used by the macOS target.
    init() {
        let launchState = CoachSyncContainer.make()
        container = launchState.container
        launchErrorMessage = launchState.launchErrorMessage
        // Matches the iOS entry point: under UI testing, a fake already-approved session backed by
        // an in-memory store — never the real Keychain or the live backend.
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
                OnboardingGate { MacContentView() }
                    .environment(auth)
                    .environment(sync)
                    .onChange(of: auth.state) { _, _ in
                        if auth.currentSession != nil { sync.requestSync() }
                    }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active { sync.requestSync() }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: SyncStore.didSaveNotification)) { _ in
                        sync.requestSync()
                    }
                    .onReceive(NotificationCenter.default.publisher(
                        for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
                        auth.signOut()
                    }
            }
        }
        .modelContainer(container)
        .defaultSize(width: 1100, height: 700)
    }
}
