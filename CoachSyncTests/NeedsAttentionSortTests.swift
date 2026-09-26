import XCTest
import SwiftData
@testable import CoachSync

/// Coverage for `NeedsAttentionSection.alertsSortedForDisplay` — the app-side half of rule 10
/// (lastName→firstName case-insensitive sort, ≤5-row cap). Mirrors the backend's
/// `NeedsAttentionControllerTest`. Previously only 0/1-flagged-athlete cases were exercised on
/// either stack, so a tie-break or cap-boundary regression could ship with a fully green suite.
final class NeedsAttentionSortTests: XCTestCase {

    private func flaggedAthlete(firstName: String, lastName: String, context: ModelContext) -> Athlete {
        let athlete = Athlete(firstName: firstName, lastName: lastName, dateOfBirth: Date(timeIntervalSince1970: 0))
        context.insert(athlete)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let day: TimeInterval = 86_400
        for (offset, time) in [(0, 120_000), (1, 124_000), (2, 128_000)] {
            let session = CoachSession(sessionName: "Session", scheduledDate: base + Double(offset) * day)
            let block = SessionBlock(blockName: "500m TT", blockType: .paddleTimePieces, sortOrder: 0, session: session)
            let record = PerformanceRecord(athlete: athlete, sessionBlock: block, repNumber: 1,
                                            recordedTimeMs: time, status: .complete)
            context.insert(session)
            context.insert(block)
            context.insert(record)
        }
        return athlete
    }

    func testTieBreak_sameLastName_ordersByFirstNameCaseInsensitively() throws {
        let context = try TestSupport.makeInMemoryContext()
        let zed = flaggedAthlete(firstName: "zed", lastName: "Smith", context: context)
        let amy = flaggedAthlete(firstName: "Amy", lastName: "smith", context: context)
        try context.save()
        XCTAssertEqual(zed.decliningBlockName, "500m TT", "sanity: both athletes must actually be flagged")

        let alerts = NeedsAttentionSection.alertsSortedForDisplay(from: [zed, amy])

        XCTAssertEqual(alerts.map { $0.athlete.firstName }, ["Amy", "zed"],
                       "same last name (case-insensitive) must tie-break on first name")
    }

    func testCapBoundary_moreThanFiveFlagged_prefixFiveKeepsAlphabeticalOrder() throws {
        let context = try TestSupport.makeInMemoryContext()
        let names = ["Gary", "Alice", "Frank", "Diane", "Bob", "Eve", "Carl"]  // 7, scrambled
        let athletes = names.map { flaggedAthlete(firstName: $0, lastName: $0, context: context) }
        try context.save()

        let alerts = NeedsAttentionSection.alertsSortedForDisplay(from: athletes)

        XCTAssertEqual(alerts.count, 7, "the full flagged count (used for the badge) must not be pre-capped")
        XCTAssertEqual(alerts.map { $0.athlete.firstName },
                       ["Alice", "Bob", "Carl", "Diane", "Eve", "Frank", "Gary"])
        XCTAssertEqual(Array(alerts.prefix(5)).map { $0.athlete.firstName },
                       ["Alice", "Bob", "Carl", "Diane", "Eve"],
                       "the rendered 5-row cap must keep the first five in sorted order, not insertion order")
    }
}
