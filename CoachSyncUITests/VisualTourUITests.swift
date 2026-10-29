import XCTest

/// Visual tour: walks every primary screen and the core logging flow,
/// attaching a full-screen screenshot at each stop (kept in the .xcresult
/// even on success). Used for visual review — run it under light/dark
/// appearance and the large-text variant, then export the attachments:
///
///     xcrun xcresulttool export attachments --path <result>.xcresult --output-path <dir>
///
/// Assertions are deliberately limited to "the screen we navigated to
/// exists", so one missing control fails loudly at the right stop instead
/// of silently screenshotting the wrong screen.
final class VisualTourUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testVisualTour() throws {
        launch()
        runTour()
    }

    /// Same tour at the largest accessibility text size, to catch truncation
    /// and clipped layouts that only appear with Dynamic Type.
    func testVisualTourAccessibilityTextSize() throws {
        launch(extraArguments: ["-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryAccessibilityXL"])
        runTour()
    }

    // MARK: - Tour

    private func runTour() {
        snap("01-home-empty")

        // Athletes: list, new-athlete form, a second athlete saved.
        app.tab(.athletes).tap()
        XCTAssertTrue(app.navigationBars["Athletes"].waitForExistence(timeout: 3))
        snap("02-athletes")

        app.buttons["athletes.addButton"].tap()
        let firstName = app.textFields["athlete.firstNameField"]
        XCTAssertTrue(firstName.waitForExistence(timeout: 3))
        firstName.tap()
        firstName.typeText("Jordan")
        let lastName = app.textFields["athlete.lastNameField"]
        lastName.tap()
        lastName.typeText("Rivers")
        snap("03-new-athlete")
        app.buttons["athlete.saveButton"].tap()
        XCTAssertTrue(app.staticTexts["Jordan Rivers"].waitForExistence(timeout: 3))
        snap("04-athletes-two")

        // Teams: empty state, new team, team detail.
        app.tab(.teams).tap()
        XCTAssertTrue(app.navigationBars["Teams"].waitForExistence(timeout: 3))
        snap("05-teams-empty")

        app.buttons["Add team"].tap()
        XCTAssertTrue(app.navigationBars["New Team"].waitForExistence(timeout: 3))
        let teamName = app.textFields.firstMatch
        teamName.tap()
        teamName.typeText("Sprint A Squad")
        snap("06-new-team")
        app.navigationBars["New Team"].buttons["Create"].tap()
        let teamCell = app.staticTexts["Sprint A Squad"]
        XCTAssertTrue(teamCell.waitForExistence(timeout: 3))
        snap("07-teams-one")
        teamCell.tap()
        XCTAssertTrue(app.navigationBars["Sprint A Squad"].waitForExistence(timeout: 3))
        snap("08-team-detail")

        // Schedule and Settings.
        app.tab(.schedule).tap()
        XCTAssertTrue(app.navigationBars["Schedule"].waitForExistence(timeout: 3))
        snap("09-schedule")

        app.tab(.settings).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        snap("10-settings")
        app.swipeUp()
        snap("11-settings-scrolled")

        // Core flow: create a practice, take attendance, log a time, complete.
        app.tab(.home).tap()
        app.buttons["dashboard.addPracticeButton"].tap()
        XCTAssertTrue(app.navigationBars["New Practice"].waitForExistence(timeout: 3))
        snap("12-new-practice")

        // At accessibility sizes the button sits below the fold of a lazy Form.
        let addBlock = app.buttons["session.addBlockButton"]
        for _ in 0..<4 where !addBlock.exists { app.swipeUp() }
        addBlock.tap()
        XCTAssertTrue(app.navigationBars["Add Block"].waitForExistence(timeout: 3))
        let distance = app.textFields["block.distanceField"]
        XCTAssertTrue(distance.waitForExistence(timeout: 3))
        distance.tap()
        distance.typeText("1000")
        snap("13-add-block")
        app.buttons["block.addButton"].tap()
        XCTAssertTrue(app.navigationBars["New Practice"].waitForExistence(timeout: 3))
        snap("14-new-practice-with-block")
        app.buttons["session.saveButton"].tap()

        let card = app.buttons["dashboard.todaySessionCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        snap("15-home-with-practice")

        card.tap()
        XCTAssertTrue(app.navigationBars["Attendance"].waitForExistence(timeout: 3))
        snap("16-attendance")
        app.buttons["attendance.markAllPresentButton"].tap()
        snap("17-attendance-all-present")
        app.buttons["Next"].tap()

        XCTAssertTrue(app.navigationBars["Block 1 of 1"].waitForExistence(timeout: 3))
        snap("18-block-entry")
        let rep = app.textFields["block.repField"].firstMatch
        XCTAssertTrue(rep.waitForExistence(timeout: 3))
        rep.tap()
        rep.typeText("4:05.3\n")
        snap("19-block-entry-filled")
        app.buttons["blockEntry.nextButton"].tap()

        XCTAssertTrue(app.navigationBars["Summary"].waitForExistence(timeout: 3))
        snap("20-summary")
        app.swipeUp()
        snap("21-summary-scrolled")
        app.buttons["session.completeButton"].tap()
        XCTAssertTrue(app.buttons["dashboard.addPracticeButton"].waitForExistence(timeout: 3))
        snap("22-home-after-complete")

        // Athlete profile, top and scrolled.
        app.tab(.athletes).tap()
        let athlete = app.staticTexts["Jordan Rivers"]
        XCTAssertTrue(athlete.waitForExistence(timeout: 3))
        athlete.tap()
        sleep(1)
        snap("23-athlete-profile")
        app.swipeUp()
        snap("24-athlete-profile-scrolled")
        app.swipeUp()
        snap("25-athlete-profile-scrolled-more")
    }

    // MARK: - Helpers

    private func launch(extraArguments: [String] = []) {
        app.launchArguments = ["UI_TESTING", "-currentCoachID", "00000000-0000-0000-0000-000000000001"]
            + extraArguments
        app.launch()
        // The tab bar renders a beat before its buttons join the accessibility tree.
        XCTAssertTrue(app.tab(.home).waitForExistence(timeout: 10))
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
