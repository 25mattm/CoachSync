import XCTest

/// Golden path: the Dashboard's "Add Practice" sheet opens and cancels
/// cleanly — the same modal-sheet shape reused by session/block/athlete
/// sheets throughout the app.
final class SessionSheetUITests: CoachSyncUITestCase {

    func testDashboardAddPracticeSheetOpensAndCancels() throws {
        app.buttons["dashboard.addPracticeButton"].tap()
        XCTAssertTrue(app.navigationBars["New Practice"].waitForExistence(timeout: 2))

        app.buttons["session.cancelButton"].tap()
        XCTAssertFalse(app.navigationBars["New Practice"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["dashboard.addPracticeButton"].waitForExistence(timeout: 2))
    }
}
