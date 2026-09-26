/// Codable mirrors of the backend's auth DTOs (`AppleSignInRequest` / `AuthResponse` /
/// `CoachResponse`). Kept deliberately small — Stage 1 only needs the sign-in exchange.

import Foundation

/// Request body for `POST /api/auth/apple`. `displayName` is Apple's full name, which is
/// only delivered on the first authorization (and never inside the identity token), so the
/// app forwards it so a newly provisioned coach can be named.
struct AppleSignInRequestDTO: Encodable {
    let identityToken: String
    let displayName: String?
}

/// Response from `POST /api/auth/apple`: the backend session token, the signed-in coach, and their
/// club — `nil` while pending approval (multi-club tenancy). `clubId` lives here rather than on
/// `CoachDTO`: that struct mirrors the general-purpose synced coach roster and must not gain a
/// sign-in-only field (see the backend's `CoachResponse`, pinned by `WireContractTest`).
struct AuthResponseDTO: Decodable {
    let token: String
    let expiresAt: Date
    let coach: CoachDTO
    let clubId: UUID?
}

/// Request body for `POST /api/clubs/join` — a pending coach registering intent to join a club.
struct JoinClubRequestDTO: Encodable {
    let joinCode: String
}

/// A coach as represented by the backend API.
struct CoachDTO: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let role: String?
    let nccpLevel: String?
    let colorHex: String?
    let createdAt: Date
    /// Optional so a Stage-1/2 auth response (which predates the field) still decodes; the sync
    /// pull always receives it and uses it for last-write-wins.
    var updatedAt: Date?
}

extension JSONDecoder {

    /// Decoder configured for the backend's JSON: Spring/Jackson serializes `Instant` as an
    /// ISO-8601 string, with or without fractional seconds depending on the value, so this
    /// accepts both forms.
    static let backend: JSONDecoder = {
        let decoder = JSONDecoder()
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = withFractional.date(from: raw) ?? plain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Not an ISO-8601 date: \(raw)"))
        }
        return decoder
    }()
}

extension JSONEncoder {

    /// Encoder used for persisting a session locally (ISO-8601 dates, round-trips with
    /// `JSONDecoder.backend`).
    static let backend: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
