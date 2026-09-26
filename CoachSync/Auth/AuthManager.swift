/// Observable owner of the backend session. Stage 1: restore a saved session at launch,
/// exchange an Apple identity token for a session, and sign out. No app data flows through
/// the backend yet — that arrives with the sync stages.

import Foundation
import Observation

@MainActor
@Observable
final class AuthManager {

    enum State: Equatable {
        case signedOut
        case signedIn(StoredSession)
    }

    private(set) var state: State = .signedOut
    /// Non-nil after a failed sign-in, for display.
    var errorMessage: String?
    /// True while a sign-in network exchange is in flight.
    private(set) var isAuthenticating = false

    private let client: BackendClient
    private let store: TokenStoring

    init(client: BackendClient = BackendClient(), store: TokenStoring = KeychainTokenStore()) {
        self.client = client
        self.store = store
    }

    var currentSession: StoredSession? {
        if case let .signedIn(session) = state { return session }
        return nil
    }

    /// Loads any persisted session at launch.
    func restore() {
        if let session = store.load() {
            state = .signedIn(session)
        }
    }

    /// Exchanges an Apple identity token for a backend session and persists it.
    func signIn(identityToken: String, displayName: String?) async {
        errorMessage = nil
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let response = try await client.signInWithApple(
                identityToken: identityToken, displayName: displayName)
            let session = StoredSession(
                token: response.token, expiresAt: response.expiresAt,
                coach: response.coach, clubId: response.clubId)
            try store.save(session)
            state = .signedIn(session)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func signOut() {
        try? store.clear()
        state = .signedOut
    }

    /// Outcome of ``joinClub(code:)`` — mirrors the backend's `POST /api/clubs/join` responses.
    enum JoinClubResult {
        /// Request recorded; still pending an operator's approval.
        case success
        /// Already had a pending request (a harmless re-submission, not an error to show loudly).
        case alreadyPending
        /// No club matches that code.
        case invalidCode
        case failure(String)
    }

    /// Registers intent to join the club behind `code`. Never grants access by itself — the coach
    /// stays pending until an operator approves them (see the multi-club tenancy plan's slice 4).
    func joinClub(code: String) async -> JoinClubResult {
        guard let token = currentSession?.token else {
            return .failure("Sign in required.")
        }
        do {
            let request = try client.jsonRequest(
                path: "/api/clubs/join", method: "POST", token: token,
                body: JoinClubRequestDTO(joinCode: code))
            switch try await client.sendForStatus(request) {
            case 200...299: return .success
            case 404: return .invalidCode
            case 409: return .alreadyPending
            default: return .failure("Something went wrong. Please try again.")
            }
        } catch {
            return .failure(Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case BackendError.unauthorized:
            return "Apple sign-in was rejected by the club server."
        case BackendError.transport:
            return "Couldn't reach the club server. Check your connection and that the backend is running."
        default:
            return "Sign-in failed. Please try again."
        }
    }
}
