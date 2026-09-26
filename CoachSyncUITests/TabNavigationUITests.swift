import XCTest

/// Golden path: every tab in the root `TabView` reaches its destination.
final class TabNavigationUITests: CoachSyncUITestCase {

    func testTabBarNavigatesAllFiveSections() throws {
        app.tabBars.buttons["tab.athletes"].tap()
        XCTAssertTrue(app.navigationBars["Athletes"].waitForExistence(timeout: 2))

        app.tabBars.buttons["tab.teams"].tap()
        XCTAssertTrue(app.navigationBars["Teams"].waitForExistence(timeout: 2))

        app.tabBars.buttons["tab.schedule"].tap()
        XCTAssertTrue(app.navigationBars["Schedule"].waitForExistence(timeout: 2))

        app.tabBars.buttons["tab.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2))

        app.tabBars.buttons["tab.home"].tap()
        XCTAssertTrue(app.tabBars.buttons["tab.home"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.tabBars.buttons["tab.home"].isSelected)
    }
}
