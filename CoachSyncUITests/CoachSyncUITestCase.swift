import XCTest

/// Shared UI-test base: launches a fresh, in-memory instance of the app with
/// onboarding pre-satisfied via a fixed seeded coach (see
/// `CoachSyncContainer.uiTestCoachID` / `makeUITestingContainer()` in
/// SharedContainer.swift), so tests exercise their own golden path instead of
/// the onboarding flow on every run.
class CoachSyncUITestCase: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["UI_TESTING", "-currentCoachID", "00000000-0000-0000-0000-000000000001"]
        app.launch()
    }
}
