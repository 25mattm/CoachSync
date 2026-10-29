import XCTest

/// Golden path: every tab in the root `TabView` reaches its destination.
final class TabNavigationUITests: CoachSyncUITestCase {

    func testTabBarNavigatesAllFiveSections() throws {
        app.tab(.athletes).tap()
        XCTAssertTrue(app.navigationBars["Athletes"].waitForExistence(timeout: 2))

        app.tab(.teams).tap()
        XCTAssertTrue(app.navigationBars["Teams"].waitForExistence(timeout: 2))

        app.tab(.schedule).tap()
        XCTAssertTrue(app.navigationBars["Schedule"].waitForExistence(timeout: 2))

        app.tab(.settings).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2))

        app.tab(.home).tap()
        XCTAssertTrue(app.tab(.home).waitForExistence(timeout: 2))
        XCTAssertTrue(app.tab(.home).isSelected)
    }
}
