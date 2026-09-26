import XCTest

/// Golden path: the core coaching workflow — create a practice with one
/// block, mark attendance, log the block's result, and complete the
/// session. Exercises `SessionLoggerView`'s full phase chain (attendance →
/// block entry → summary), including the per-rep `TimeTextField` entry the
/// 2026-07-06 keyboard-lag fix touched, and doubles as a regression test for
/// the 2026-07-09 "Mark All Present" mis-tap fix (`.buttonStyle(.plain)`).
final class SessionLoggingUITests: CoachSyncUITestCase {

    func testCreateLogAndCompleteASession() throws {
        // Create a practice with one Paddle Distance block.
        app.buttons["dashboard.addPracticeButton"].tap()
        XCTAssertTrue(app.navigationBars["New Practice"].waitForExistence(timeout: 2))

        app.buttons["session.addBlockButton"].tap()
        XCTAssertTrue(app.navigationBars["Add Block"].waitForExistence(timeout: 2))

        let distanceField = app.textFields["block.distanceField"]
        XCTAssertTrue(distanceField.waitForExistence(timeout: 2))
        distanceField.tap()
        distanceField.typeText("1000")

        app.buttons["block.addButton"].tap()
        XCTAssertTrue(app.navigationBars["New Practice"].waitForExistence(timeout: 2))

        app.buttons["session.saveButton"].tap()
        XCTAssertTrue(app.buttons["dashboard.addPracticeButton"].waitForExistence(timeout: 2))

        // Open the logger and explicitly tap Mark All Present — this is also
        // the regression check for the 2026-07-09 mis-tap bug (adjacent
        // Buttons in a List row need `.buttonStyle(.plain)` or the tap
        // silently routes to the wrong button's action).
        app.buttons["dashboard.todaySessionCard"].tap()
        XCTAssertTrue(app.navigationBars["Attendance"].waitForExistence(timeout: 2))
        app.buttons["attendance.markAllPresentButton"].tap()
        XCTAssertTrue(app.staticTexts["1 of 1 present"].waitForExistence(timeout: 2))
        app.buttons["Next"].tap()

        // Log the block's result.
        XCTAssertTrue(app.navigationBars["Block 1 of 1"].waitForExistence(timeout: 2))
        let repField = app.textFields["block.repField"]
        XCTAssertTrue(repField.waitForExistence(timeout: 2))
        repField.tap()
        repField.typeText("1:30\n")
        app.buttons["blockEntry.nextButton"].tap()

        // Complete the session.
        XCTAssertTrue(app.navigationBars["Summary"].waitForExistence(timeout: 2))
        app.buttons["session.completeButton"].tap()

        // The logger dismisses back to the Dashboard on success.
        XCTAssertTrue(app.buttons["dashboard.addPracticeButton"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["Summary"].exists)
    }
}
