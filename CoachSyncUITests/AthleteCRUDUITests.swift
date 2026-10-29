import XCTest

/// Golden path: adding an athlete through the New Athlete form persists and
/// appears back in the roster — a full write-then-read-back round trip
/// through `SyncStore.save` and the Athletes list's `@Query`.
final class AthleteCRUDUITests: CoachSyncUITestCase {

    func testAddAthleteAppearsInRoster() throws {
        app.tab(.athletes).tap()
        XCTAssertTrue(app.navigationBars["Athletes"].waitForExistence(timeout: 2))

        app.buttons["athletes.addButton"].tap()

        let firstNameField = app.textFields["athlete.firstNameField"]
        XCTAssertTrue(firstNameField.waitForExistence(timeout: 2))
        firstNameField.tap()
        firstNameField.typeText("Test")

        let lastNameField = app.textFields["athlete.lastNameField"]
        lastNameField.tap()
        lastNameField.typeText("Athlete")

        app.buttons["athlete.saveButton"].tap()

        XCTAssertTrue(app.staticTexts["Test Athlete"].waitForExistence(timeout: 2))
    }
}
