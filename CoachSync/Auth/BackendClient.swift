/// Minimal async client for the CoachSync backend REST API. Stage 1 only exercises the
/// sign-in exchange; the bearer-authorized request helper is here for the sync stages.

import Foundation

/// Errors surfaced by ``BackendClient``.
enum BackendError: Error, Equatable {
    /// The server rejected the credential (HTTP 401) — e.g. a bad/expired token.
    case unauthorized
    /// A non-success status other than 401.
    case http(Int)
    /// The request never completed (offline, DNS, TLS, …).
    case transport
    /// A 2xx body that didn't decode to the expected type.
    case decoding
}

/// Async wrapper over `URLSession` for the backend. The `URLSession` is injectable so tests
/// can stub responses with a `URLProtocol`.
struct BackendClient {

    let baseURL: URL
    let session: URLSession

    // `nonisolated` (the module defaults to MainActor isolation): the init only stores two
    // Sendable values and touches no isolated state, so it stays callable from the nonisolated
    // default-argument expressions (`= BackendClient()`) in AuthManager/SyncCoordinator/SyncService.
    // The client's *methods* remain MainActor-isolated — the whole backend/DTO layer runs there.
    nonisolated init(baseURL: URL = BackendConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Exchanges an Apple identity token for a backend session (creating/linking the coach
    /// on first sign-in).
    func signInWithApple(identityToken: String, displayName: String?) async throws -> AuthResponseDTO {
        var request = URLRequest(url: baseURL.appending(path: "/api/auth/apple"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            AppleSignInRequestDTO(identityToken: identityToken, displayName: displayName))
        return try await send(request, decodeTo: AuthResponseDTO.self)
    }

    /// Builds a bearer-authorized request for a backend path that may include a `?query`. The path
    /// part goes through `appending(path:)` (so it keeps any path prefix on `baseURL`, e.g. a
    /// reverse-proxy mount), while the query is set as an actual query — `appending(path:)` alone
    /// would percent-encode the "?" into the path and mangle pagination params.
    func authorizedRequest(path: String, method: String = "GET", token: String) -> URLRequest {
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var url = baseURL.appending(path: String(parts[0]))
        if parts.count == 2, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.percentEncodedQuery = String(parts[1])
            url = components.url ?? url
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Authorized GET decoding a plain list body (`List<…>` endpoints).
    func getList<T: Decodable>(_ path: String, token: String) async throws -> [T] {
        try await send(authorizedRequest(path: path, token: token), decodeTo: [T].self)
    }

    /// Authorized GET over a Spring `PagedModel` endpoint, returning the content. Requests a
    /// large page so a club fits in one round-trip; loops if the server reports more pages.
    func getPaged<T: Decodable>(_ path: String, token: String, pageSize: Int = 500) async throws -> [T] {
        let separator = path.contains("?") ? "&" : "?"
        var page = try await send(
            authorizedRequest(path: "\(path)\(separator)size=\(pageSize)&page=0", token: token),
            decodeTo: PageDTO<T>.self)
        var items = page.content
        var next = 1
        while let info = page.page, next < info.totalPages {
            page = try await send(
                authorizedRequest(path: "\(path)\(separator)size=\(pageSize)&page=\(next)", token: token),
                decodeTo: PageDTO<T>.self)
            items.append(contentsOf: page.content)
            next += 1
        }
        return items
    }

    /// Sends a request and decodes a 2xx body, mapping status/transport failures to
    /// ``BackendError``.
    func send<T: Decodable>(_ request: URLRequest, decodeTo: T.Type) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BackendError.transport
        }
        guard let http = response as? HTTPURLResponse else { throw BackendError.transport }
        switch http.statusCode {
        case 200...299:
            do {
                return try JSONDecoder.backend.decode(T.self, from: data)
            } catch {
                throw BackendError.decoding
            }
        case 401:
            throw BackendError.unauthorized
        default:
            throw BackendError.http(http.statusCode)
        }
    }
}

extension BackendClient {

    /// Builds a bearer + JSON-body request (the write/push path).
    func jsonRequest<Body: Encodable>(
        path: String, method: String, token: String, body: Body) throws -> URLRequest {
        var request = authorizedRequest(path: path, method: method, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// Sends a write request and returns its HTTP status code — the pusher decides the outcome from
    /// the status (success / 401 re-auth / 409 drop / 404 already-gone / transient). The body is
    /// ignored. Transport failures throw ``BackendError/transport``.
    func sendForStatus(_ request: URLRequest) async throws -> Int {
        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw BackendError.transport
        }
        guard let http = response as? HTTPURLResponse else { throw BackendError.transport }
        return http.statusCode
    }
}
