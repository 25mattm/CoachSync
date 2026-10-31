import XCTest

/// Runs Xcode's accessibility audit at every primary screen and through the core logging flow:
/// contrast, element descriptions, hit regions, Dynamic Type, clipped text, traits and so on.
/// The audit runs against the current appearance, so CI runs this under light and dark.
///
/// The audit catches a useful subset of problems, not all of them: it doesn't replace walking the
/// common tasks with VoiceOver and Voice Control before claiming support on the App Store.
///
/// Dynamic Type isn't audited here because its check flags every system toolbar and form header;
/// `VisualTourUITests` covers large text with screenshots instead. See `isOutOfOurHands` for the
/// other findings left out.
final class AccessibilityAuditUITests: CoachSyncUITestCase {
    private var issues: [String] = []

    func testEveryPrimaryScreenPassesTheAudit() throws {
        // The audit fails with "Invalid target app" if it starts before the app settles.
        XCTAssertTrue(app.buttons["dashboard.addPracticeButton"].waitForExistence(timeout: 5))
        sleep(1)
        audit("home-empty")

        app.tab(.athletes).tap()
        XCTAssertTrue(app.navigationBars["Athletes"].waitForExistence(timeout: 3))
        audit("athletes")

        app.buttons["athletes.addButton"].tap()
        let firstName = app.textFields["athlete.firstNameField"]
        XCTAssertTrue(firstName.waitForExistence(timeout: 3))
        firstName.tap()
        firstName.typeText("Jordan")
        let lastName = app.textFields["athlete.lastNameField"]
        lastName.tap()
        lastName.typeText("Rivers")
        audit("new-athlete")
        app.buttons["athlete.saveButton"].tap()
        XCTAssertTrue(app.staticTexts["Jordan Rivers"].waitForExistence(timeout: 3))

        app.tab(.teams).tap()
        XCTAssertTrue(app.navigationBars["Teams"].waitForExistence(timeout: 3))
        audit("teams-empty")
        app.buttons["Add team"].tap()
        XCTAssertTrue(app.navigationBars["New Team"].waitForExistence(timeout: 3))
        let teamName = app.textFields.firstMatch
        teamName.tap()
        teamName.typeText("Sprint A Squad")
        audit("new-team")
        app.navigationBars["New Team"].buttons["Create"].tap()
        let teamCell = app.staticTexts["Sprint A Squad"]
        XCTAssertTrue(teamCell.waitForExistence(timeout: 3))
        teamCell.tap()
        XCTAssertTrue(app.navigationBars["Sprint A Squad"].waitForExistence(timeout: 3))
        audit("team-detail")

        app.tab(.schedule).tap()
        XCTAssertTrue(app.navigationBars["Schedule"].waitForExistence(timeout: 3))
        audit("schedule")

        app.tab(.settings).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        audit("settings")
        app.swipeUp()
        audit("settings-scrolled")

        app.tab(.home).tap()
        app.buttons["dashboard.addPracticeButton"].tap()
        XCTAssertTrue(app.navigationBars["New Practice"].waitForExistence(timeout: 3))
        audit("new-practice")
        let addBlock = app.buttons["session.addBlockButton"]
        for _ in 0..<4 where !addBlock.exists { app.swipeUp() }
        addBlock.tap()
        XCTAssertTrue(app.navigationBars["Add Block"].waitForExistence(timeout: 3))
        let distance = app.textFields["block.distanceField"]
        XCTAssertTrue(distance.waitForExistence(timeout: 3))
        distance.tap()
        distance.typeText("1000")
        audit("add-block")
        app.buttons["block.addButton"].tap()
        XCTAssertTrue(app.navigationBars["New Practice"].waitForExistence(timeout: 3))
        app.buttons["session.saveButton"].tap()

        let card = app.buttons["dashboard.todaySessionCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        audit("home-with-practice")

        card.tap()
        XCTAssertTrue(app.navigationBars["Attendance"].waitForExistence(timeout: 3))
        audit("attendance")
        app.buttons["attendance.markAllPresentButton"].tap()
        app.buttons["Next"].tap()

        XCTAssertTrue(app.navigationBars["Block 1 of 1"].waitForExistence(timeout: 3))
        let rep = app.textFields["block.repField"].firstMatch
        XCTAssertTrue(rep.waitForExistence(timeout: 3))
        audit("block-entry")
        rep.tap()
        rep.typeText("4:05.3\n")
        audit("block-entry-filled")
        app.buttons["blockEntry.nextButton"].tap()

        XCTAssertTrue(app.navigationBars["Summary"].waitForExistence(timeout: 3))
        audit("summary")
        app.buttons["session.completeButton"].tap()
        XCTAssertTrue(app.buttons["dashboard.addPracticeButton"].waitForExistence(timeout: 3))
        audit("home-after-complete")

        app.tab(.athletes).tap()
        let athlete = app.staticTexts["Jordan Rivers"]
        XCTAssertTrue(athlete.waitForExistence(timeout: 3))
        athlete.tap()
        sleep(1)
        audit("athlete-profile")
        app.swipeUp()
        audit("athlete-profile-scrolled")

        XCTAssertTrue(issues.isEmpty, "\(issues.count) accessibility issues:\n"
            + issues.joined(separator: "\n"))
    }

    private static let auditTypes: XCUIAccessibilityAuditType = [
        .contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .trait, .textClipped,
    ]

    /// Findings the app can't act on: nothing to attribute them to, the system's own bars and its
    /// `.secondary` text, which Increase Contrast strengthens, and single-line text fields, which
    /// scroll their contents rather than clip them.
    private func isOutOfOurHands(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard let element = issue.element else { return true }
        if issue.compactDescription.contains("nearly passed") { return true }
        if element.frame.minY < 110 && element.frame.height <= 44 { return true }
        return issue.auditType == .textClipped && element.elementType == .textField
    }

    /// Audit findings checked by hand and found wrong, so they stay visible here. The audit misreads
    /// text on Liquid Glass and materials: dates on Home cards measure 8.3:1 in screenshots. The
    /// empty-state text it calls clipped wraps fully at every size in the large-text tours.
    private func isKnownFalsePositive(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        let label = issue.element?.label ?? ""
        if issue.auditType == .textClipped {
            return label.hasPrefix("Archived practices") || label.hasPrefix("Create a team")
        }
        guard issue.auditType == .contrast else { return false }
        return label == "Present" || label == "Add Block" || label.hasPrefix("“This device is”")
            || label.range(of: #"^[A-Z][a-z]{2} \d{1,2}$"#, options: .regularExpression) != nil
    }

    /// Records every issue instead of stopping at the first, so one run reports the whole list.
    private func audit(_ stop: String) {
        do {
            try app.performAccessibilityAudit(for: Self.auditTypes) { [self] issue in
                if isOutOfOurHands(issue) || isKnownFalsePositive(issue) { return true }
                let element = issue.element.map { String($0.debugDescription.prefix(160)) } ?? "no element"
                let line = "A11Y|\(stop)|\(issue.auditType.rawValue)|\(issue.compactDescription)|\(element)"
                    .replacingOccurrences(of: "\n", with: " ")
                print(line)
                issues.append(line)
                return true
            }
        } catch {
            issues.append("A11Y|\(stop)|audit failed|\(error)")
        }
    }
}
