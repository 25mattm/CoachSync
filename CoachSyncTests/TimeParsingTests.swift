import XCTest
@testable import CoachSync

final class TimeParsingTests: XCTestCase {
    func testParsesSupportedMinuteSecondFormats() {
        XCTAssertEqual(parseTimeToMs("1:05.2"), 65_200)
        XCTAssertEqual(parseTimeToMs("1:05.23"), 65_230)
        XCTAssertEqual(parseTimeToMs("1:05.234"), 65_234)
        XCTAssertEqual(parseTimeToMs(" 1:05.23 "), 65_230)
    }

    func testParsesSupportedSecondAndHourFormats() {
        XCTAssertEqual(parseTimeToMs("34.12"), 34_120)
        XCTAssertEqual(parseTimeToMs("65"), 65_000)
        XCTAssertEqual(parseTimeToMs("1:02:03.45"), 3_723_450)
        XCTAssertEqual(parseTimeToMs("1:02:03:456"), 3_723_456)
    }

    func testRejectsImpossibleOrAmbiguousTimes() {
        // These values should stay out of SwiftData instead of becoming misleading results.
        XCTAssertNil(parseTimeToMs(""))
        XCTAssertNil(parseTimeToMs("abc"))
        XCTAssertNil(parseTimeToMs("-1:05"))
        XCTAssertNil(parseTimeToMs("1::05"))
        XCTAssertNil(parseTimeToMs("1:75.00"))
        XCTAssertNil(parseTimeToMs("0:99"))
        XCTAssertNil(parseTimeToMs("34.1234"))
        XCTAssertNil(parseTimeToMs("1:05.2349"))
        XCTAssertNil(parseTimeToMs("1:60:00:000"))   // minute out of range (4-part form)
        XCTAssertNil(parseTimeToMs("1:02:99:000"))   // second out of range (4-part form)
    }

    func testParsesSingleDigitSecondsAndLongMinuteCounts() {
        XCTAssertEqual(parseTimeToMs("1:5"), 65_000)          // "1:5" reads as 1:05
        XCTAssertEqual(parseTimeToMs("75:00.0"), 4_500_000)   // minutes are unbounded in M:SS form
        XCTAssertEqual(parseTimeToMs("0.5"), 500)
    }

    func testRejectsMalformedSeparators() {
        XCTAssertNil(parseTimeToMs("1:05."))       // trailing dot, empty fraction
        XCTAssertNil(parseTimeToMs("1.05.2"))      // two dots
        XCTAssertNil(parseTimeToMs("1:2:3:4:5"))   // too many colons
        XCTAssertNil(parseTimeToMs("1:05.2a"))
        XCTAssertNil(parseTimeToMs(":05"))
    }

    func testBareSecondsWithFractionAbove59() {
        // Bare seconds have no minutes part, so "65.5" is as valid as "65" (a 400m split).
        // The 0–59 cap still applies once there is a minutes part.
        XCTAssertEqual(parseTimeToMs("65"), 65_000)
        XCTAssertEqual(parseTimeToMs("65.5"), 65_500)
        XCTAssertEqual(parseTimeToMs("125.25"), 125_250)
        XCTAssertNil(parseTimeToMs("-1.5"))
        XCTAssertNil(parseTimeToMs("1:65.5"))
    }

    func testLoggableEntryText() {
        XCTAssertTrue(isLoggableEntryText("1:30"))
        XCTAssertTrue(isLoggableEntryText(" dns "))
        XCTAssertTrue(isLoggableEntryText("Dnf"))
        XCTAssertFalse(isLoggableEntryText(""))
        XCTAssertFalse(isLoggableEntryText("   "))
        XCTAssertFalse(isLoggableEntryText("DN"))
        XCTAssertFalse(isLoggableEntryText("1:75"))
    }

    func testZeroTimeIsNotLoggable() {
        // `saveEntry` rejects a zero time, so the "fully logged" checks must too.
        XCTAssertFalse(isLoggableEntryText("0"))
        XCTAssertFalse(isLoggableEntryText("0:00.00"))
        XCTAssertTrue(isLoggableEntryText("0.01"))
    }

    func testFormatsMillisecondsForDisplay() {
        XCTAssertEqual(formatMillisecondsForDisplay(65_230), "1:05.23")
        XCTAssertEqual(formatMillisecondsForDisplay(3_723_450), "1:02:03.45")
        XCTAssertEqual(formatMillisecondsForDisplay(-1), "0:00.00")
    }

    func testFormatsSecondsForDisplay() {
        // formatSecondsForDisplay rounds to the nearest millisecond first.
        XCTAssertEqual(formatSecondsForDisplay(65.23), "1:05.23")
        XCTAssertEqual(formatSecondsForDisplay(0), "0:00.00")
        XCTAssertEqual(formatSecondsForDisplay(125), "2:05.00")
    }

    func testFormatsDurationLabel() {
        // Shared block-duration label — "45s" / "10 min" / "2:30".
        XCTAssertEqual(formatDurationLabel(45), "45s")
        XCTAssertEqual(formatDurationLabel(600), "10 min")
        XCTAssertEqual(formatDurationLabel(150), "2:30")
        XCTAssertEqual(formatDurationLabel(0), "0s")
    }

    func testFormatsChipDuration() {
        // Shared chip-style duration label — minute/second marks.
        XCTAssertEqual(formatChipDuration(240), "4'")
        XCTAssertEqual(formatChipDuration(90), "1'30\"")
        XCTAssertEqual(formatChipDuration(30), "30\"")
    }

    func testFormatsMillisecondsCoarse() {
        // Coarse formatting drops centiseconds and rounds to the nearest second.
        XCTAssertEqual(formatMillisecondsCoarse(89_700), "1:30")     // rounds up
        XCTAssertEqual(formatMillisecondsCoarse(125_000), "2:05")
        XCTAssertEqual(formatMillisecondsCoarse(3_725_000), "1:02:05")
        XCTAssertEqual(formatMillisecondsCoarse(-1), "0:00")
    }
}
