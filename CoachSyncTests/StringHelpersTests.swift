import XCTest
@testable import CoachSync

/// `String.ordinal` drives regatta placings ("1st", "22nd"), so the English
/// teen exceptions and negative inputs must read correctly.
final class OrdinalTests: XCTestCase {

    func testBasicSuffixes() {
        XCTAssertEqual(String.ordinal(1), "1st")
        XCTAssertEqual(String.ordinal(2), "2nd")
        XCTAssertEqual(String.ordinal(3), "3rd")
        XCTAssertEqual(String.ordinal(4), "4th")
        XCTAssertEqual(String.ordinal(0), "0th")
    }

    func testTeensAlwaysUseTh() {
        // 11/12/13 (and 111/112/113) are the classic exceptions.
        for n in [11, 12, 13, 111, 112, 113] {
            XCTAssertEqual(String.ordinal(n), "\(n)th", "\(n)")
        }
    }

    func testTwentiesAndHundredsFollowOnesDigit() {
        XCTAssertEqual(String.ordinal(21), "21st")
        XCTAssertEqual(String.ordinal(22), "22nd")
        XCTAssertEqual(String.ordinal(23), "23rd")
        XCTAssertEqual(String.ordinal(101), "101st")
        XCTAssertEqual(String.ordinal(1_002), "1002nd")
    }

    func testNegativeNumbersKeepAGrammaticalSuffix() {
        XCTAssertEqual(String.ordinal(-1), "-1st")
        XCTAssertEqual(String.ordinal(-12), "-12th")
        XCTAssertEqual(String.ordinal(-23), "-23rd")
    }
}
