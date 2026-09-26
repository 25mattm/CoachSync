/// Persistence for the backend session. The protocol lets the app use the Keychain while
/// tests/previews use an in-memory store (the Keychain is unreliable under unit tests).

import Foundation

/// The locally stored backend session: bearer token, its expiry, the signed-in coach, and their
/// club. `clubId` is `nil` while the coach is pending approval — a snapshot from the last sign-in,
/// not re-verified live; a coach who signs in again after being approved (or removed) gets a fresh
/// session with an up-to-date value.
struct StoredSession: Codable, Equatable {
    let token: String
    let expiresAt: Date
    let coach: CoachDTO
    let clubId: UUID?

    /// True once the token is at/after its expiry (callers re-authenticate).
    var isExpired: Bool { Date() >= expiresAt }
}

/// Abstracts where the session is persisted.
protocol TokenStoring {
    func load() -> StoredSession?
    func save(_ session: StoredSession) throws
    func clear() throws
}

/// In-memory store for tests and SwiftUI previews.
final class InMemoryTokenStore: TokenStoring {
    private var session: StoredSession?
    init(_ session: StoredSession? = nil) { self.session = session }
    func load() -> StoredSession? { session }
    func save(_ session: StoredSession) throws { self.session = session }
    func clear() throws { session = nil }
}

/// Keychain-backed store. Persists the whole session as a single JSON generic-password
/// item in the data-protection keychain (consistent on iOS and macOS).
final class KeychainTokenStore: TokenStoring {

    enum KeychainError: Error { case unexpectedStatus(OSStatus) }

    private let service = "com.example.CoachSync.session"
    private let account = "backendSession"

    // `nonisolated` (the module defaults to MainActor, inferred onto this type via TokenStoring):
    // constructing the store touches no isolated state, so it stays callable from the nonisolated
    // default-argument expression (`store: TokenStoring = KeychainTokenStore()`) in AuthManager.init.
    nonisolated init() {}

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    func load() -> StoredSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let session = try? JSONDecoder.backend.decode(StoredSession.self, from: data) else {
            return nil
        }
        return session
    }

    func save(_ session: StoredSession) throws {
        let data = try JSONEncoder.backend.encode(session)
        SecItemDelete(baseQuery as CFDictionary)  // overwrite any existing item
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
