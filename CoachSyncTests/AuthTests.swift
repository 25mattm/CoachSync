import XCTest
@testable import CoachSync

// MARK: - URLProtocol stub

/// Intercepts `URLSession` requests so the client tests run hermetically (no network).
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// A `URLSession` wired to this stub.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Canned response for the next request.
    static func respond(status: Int, json: String) {
        handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
    }
}

/// Note `createdAt` carries fractional seconds and `expiresAt` does not — exercises both
/// branches of `JSONDecoder.backend`. `clubId` present here (an approved coach); the pending case
/// (`clubId` omitted entirely, as the backend sends it) is covered by
/// `testSignInDecodesAuthResponseWithNoClubIdWhenPending`.
private let sampleAuthJSON = """
{"token":"jwt.header.payload","expiresAt":"2026-07-18T12:00:00Z",\
"coach":{"id":"11111111-1111-1111-1111-111111111111","name":"Pat","role":"Head",\
"nccpLevel":null,"colorHex":"#3B82F6","createdAt":"2026-06-18T12:00:00.123Z"},\
"clubId":"22222222-2222-2222-2222-222222222222"}
"""

private func testClient() -> BackendClient {
    BackendClient(baseURL: URL(string: "http://test.local")!, session: StubURLProtocol.session())
}

// MARK: - BackendClient

final class BackendClientTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testSignInDecodesAuthResponseIncludingISO8601Dates() async throws {
        StubURLProtocol.respond(status: 200, json: sampleAuthJSON)

        let response = try await testClient().signInWithApple(identityToken: "apple-token", displayName: "Pat")

        XCTAssertEqual(response.token, "jwt.header.payload")
        XCTAssertEqual(response.coach.name, "Pat")
        XCTAssertEqual(response.coach.id, UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        XCTAssertEqual(response.clubId, UUID(uuidString: "22222222-2222-2222-2222-222222222222"))

        let plain = ISO8601DateFormatter()
        XCTAssertEqual(response.expiresAt, plain.date(from: "2026-07-18T12:00:00Z"))

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(response.coach.createdAt, fractional.date(from: "2026-06-18T12:00:00.123Z"))
    }

    /// The backend omits `clubId` entirely (not `null`) for a pending coach — Swift's synthesized
    /// `Decodable` for an `Optional` property already defaults a missing key to `nil`, so this pins
    /// that behavior rather than assuming it.
    func testSignInDecodesAuthResponseWithNoClubIdWhenPending() async throws {
        let pendingJSON = """
        {"token":"jwt.header.payload","expiresAt":"2026-07-18T12:00:00Z",\
        "coach":{"id":"11111111-1111-1111-1111-111111111111","name":"Pat","role":null,\
        "nccpLevel":null,"colorHex":null,"createdAt":"2026-06-18T12:00:00.123Z"}}
        """
        StubURLProtocol.respond(status: 200, json: pendingJSON)

        let response = try await testClient().signInWithApple(identityToken: "apple-token", displayName: "Pat")

        XCTAssertNil(response.clubId)
    }

    func test401MapsToUnauthorized() async {
        StubURLProtocol.respond(status: 401, json: "{}")
        do {
            _ = try await testClient().signInWithApple(identityToken: "bad", displayName: nil)
            XCTFail("expected BackendError.unauthorized")
        } catch {
            XCTAssertEqual(error as? BackendError, .unauthorized)
        }
    }

    func testAuthorizedRequestCarriesBearerHeader() {
        let request = BackendClient(baseURL: URL(string: "http://test.local")!, session: .shared)
            .authorizedRequest(path: "/api/athletes", token: "tok123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok123")
        XCTAssertEqual(request.httpMethod, "GET")
    }
}

// MARK: - AuthManager

final class AuthManagerTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    @MainActor
    private func makeManager(store: TokenStoring) -> AuthManager {
        AuthManager(client: testClient(), store: store)
    }

    @MainActor
    func testSignInStoresSessionAndFlipsState() async {
        StubURLProtocol.respond(status: 200, json: sampleAuthJSON)
        let store = InMemoryTokenStore()
        let auth = makeManager(store: store)

        await auth.signIn(identityToken: "apple-token", displayName: "Pat")

        XCTAssertEqual(auth.currentSession?.coach.name, "Pat")
        XCTAssertNotNil(store.load())
        XCTAssertNil(auth.errorMessage)
    }

    @MainActor
    func testRestoreRehydratesFromStore() {
        let session = StoredSession(
            token: "t", expiresAt: .distantFuture,
            coach: CoachDTO(id: UUID(), name: "Sam", role: nil, nccpLevel: nil, colorHex: nil, createdAt: .now),
            clubId: UUID())
        let auth = makeManager(store: InMemoryTokenStore(session))

        auth.restore()

        XCTAssertEqual(auth.currentSession?.coach.name, "Sam")
    }

    @MainActor
    func testSignOutClearsSessionAndStore() async {
        StubURLProtocol.respond(status: 200, json: sampleAuthJSON)
        let store = InMemoryTokenStore()
        let auth = makeManager(store: store)
        await auth.signIn(identityToken: "apple-token", displayName: "Pat")

        auth.signOut()

        XCTAssertNil(auth.currentSession)
        XCTAssertNil(store.load())
    }

    @MainActor
    func testDeleteAccountSignsOutOnSuccess() async {
        StubURLProtocol.respond(status: 200, json: sampleAuthJSON)
        let store = InMemoryTokenStore()
        let auth = makeManager(store: store)
        await auth.signIn(identityToken: "apple-token", displayName: "Pat")
        StubURLProtocol.respond(status: 204, json: "")

        let failure = await auth.deleteAccount(authorizationCode: "code", clientId: "com.example.CoachSync")

        XCTAssertNil(failure)
        XCTAssertNil(auth.currentSession)
        XCTAssertNil(store.load())
    }

    /// A failed delete must leave the coach signed in: they still have an account, and need to retry.
    @MainActor
    func testDeleteAccountStaysSignedInOnFailure() async {
        StubURLProtocol.respond(status: 200, json: sampleAuthJSON)
        let store = InMemoryTokenStore()
        let auth = makeManager(store: store)
        await auth.signIn(identityToken: "apple-token", displayName: "Pat")
        StubURLProtocol.respond(status: 500, json: "")

        let failure = await auth.deleteAccount(authorizationCode: "code", clientId: "com.example.CoachSync")

        XCTAssertNotNil(failure)
        XCTAssertNotNil(auth.currentSession)
        XCTAssertNotNil(store.load())
    }

    @MainActor
    func testSignInFailureSetsErrorAndStaysSignedOut() async {
        StubURLProtocol.respond(status: 401, json: "{}")
        let auth = makeManager(store: InMemoryTokenStore())

        await auth.signIn(identityToken: "bad", displayName: nil)

        XCTAssertNil(auth.currentSession)
        XCTAssertNotNil(auth.errorMessage)
    }
}
