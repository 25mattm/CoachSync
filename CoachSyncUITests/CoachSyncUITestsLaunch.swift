import XCTest

/// Launch behavior: the app comes up, and a UI-test launch is isolated from the coach's real
/// session and from the live backend.
final class CoachSyncUITestsLaunch: CoachSyncUITestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool { false }

    /// Smoke test: the seeded UI-testing launch reaches the main tab bar.
    ///
    /// This used to call `XCUIApplication().launch()` with no launch arguments, so the smoke test
    /// ran against the developer's *real* persistent store — and, with a session in the Keychain,
    /// against the live backend. It now inherits the in-memory seeded harness.
    func testLaunch() throws {
        XCTAssertTrue(app.tab(.home).waitForExistence(timeout: 10))
    }

    /// A UI-test launch must never restore the developer's real, persisted backend session.
    ///
    /// `AuthManager.restore()` reads the Keychain, which the in-memory store swap does not touch —
    /// so without the `AppEnvironment.isUITesting` gate, every test run on a machine that had ever
    /// signed in would restore that real session and push the seeded throwaway roster to the
    /// production backend. Since multi-club tenancy slice 5, `OnboardingGate` additionally requires
    /// an approved backend club, so a *fake* in-memory session (`CoachSyncContainer.uiTestSession`)
    /// is now always seeded to satisfy it — the assertion below is on the identity shown being that
    /// specific fake one, not "no session," since a leaked real session would also show *some*
    /// signed-in identity, just a different (real) one. `SyncCoordinator.syncNow()` separately
    /// no-ops under `AppEnvironment.isUITesting` regardless of the session, so this fake session
    /// exposes no path to the live backend even though "Sync Now" is now visible.
    func testUITestingLaunchDoesNotRestoreBackendSession() throws {
        app.tab(.settings).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2))

        XCTAssertTrue(app.staticTexts["UI Test Coach"].waitForExistence(timeout: 2),
                      "UI testing must show the fake seeded session, never a real restored one")
    }
}
