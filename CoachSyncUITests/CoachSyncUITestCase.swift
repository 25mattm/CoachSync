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
        // The tab bar renders a beat before its buttons join the accessibility tree.
        XCTAssertTrue(app.tab(.home).waitForExistence(timeout: 10))
    }
}

/// The root `TabView`'s tabs, by their visible label.
enum AppTab: String {
    case home = "Home", athletes = "Athletes", teams = "Teams", schedule = "Schedule", settings = "Settings"
}

extension XCUIApplication {
    /// A tab bar button, matched by label: an `.accessibilityIdentifier` set inside `.tabItem`
    /// doesn't reliably reach the UIKit tab bar button on iOS 26, so identifiers were flaky.
    /// Every UI test goes through here, so a tab-bar change is fixed in one place.
    func tab(_ tab: AppTab) -> XCUIElement {
        tabBars.buttons[tab.rawValue]
    }
}
