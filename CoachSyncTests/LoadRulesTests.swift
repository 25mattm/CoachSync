import XCTest
import SwiftData
@testable import CoachSync

/// Coverage for four "Non-Negotiable Business Rules" that had none.
///
/// Each rule below lives in exactly one function, feeds several coach-visible surfaces, and would
/// regress silently — the numbers would simply be wrong, with nothing to notice it. Pinned here:
/// - `SeasonContext.loadKilometers` — recovery km never counts toward training load.
/// - `SeasonContext.completedSessions` — load counts *completed* sessions only, inside the season year.
/// - `SeasonContext.ltadKmTarget` — the CKC LTAD target table.
/// - `CoachSession.defaultAttendanceStatus` — reviewing an old practice can't fabricate attendance.
final class LoadRulesTests: XCTestCase {

    // MARK: - Fixtures

    /// A gregorian calendar pinned to UTC so the year-boundary assertions don't depend on the
    /// machine's time zone.
    private var utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      _ hour: Int = 12, _ minute: Int = 0) -> Date {
        utcCalendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Inserts a session and saves, so the `sessionBlocks` inverse relationship is populated.
    @discardableResult
    private func makeSession(
        _ context: ModelContext,
        name: String = "Practice",
        date sessionDate: Date = Date(),
        status: SessionStatus = .completed
    ) throws -> CoachSession {
        let session = CoachSession(sessionName: name, scheduledDate: sessionDate)
        session.status = status
        context.insert(session)
        try context.save()
        return session
    }

    @discardableResult
    private func addBlock(
        _ context: ModelContext,
        to session: CoachSession,
        zone: TrainingZone?,
        distanceKm: Double? = nil,
        reps: Int = 1,
        targetMetres: Double? = nil
    ) throws -> SessionBlock {
        let block = SessionBlock(blockName: "Block", blockType: .paddleDistance, sortOrder: 0,
                                 repetitionCount: reps, session: session,
                                 trainingZone: zone, distanceKm: distanceKm)
        block.targetDistanceMetres = targetMetres
        context.insert(block)
        try context.save()
        return block
    }

    // MARK: - Recovery km is excluded from training load

    /// The headline load rule. A dropped or inverted filter here silently inflates every km figure
    /// a coach sees — Settings season stats, team seasonal load, the athlete load section, and the
    /// `SeasonArchive` totals all read through this one function.
    func testLoadKilometersExcludesRecoveryZoneAndCountsNilZone() throws {
        let context = try TestSupport.makeInMemoryContext()
        let session = try makeSession(context)

        try addBlock(context, to: session, zone: .ga1, distanceKm: 2.0)
        try addBlock(context, to: session, zone: nil, distanceKm: 1.0)       // unzoned still counts
        try addBlock(context, to: session, zone: .recovery, distanceKm: 3.0) // never counts
        try addBlock(context, to: session, zone: .ga2)                       // no distance at all

        XCTAssertEqual(SeasonContext.loadKilometers(from: [session]), 3.0, accuracy: 0.0001,
                       "recovery km must be excluded; nil-zone km must be included")
    }

    /// `effectiveDistanceKm` falls back to `reps × targetDistanceMetres` when `distanceKm` is nil,
    /// and that fallback must flow through the load sum (and still respect the recovery exclusion).
    func testLoadKilometersUsesRepsTimesTargetDistanceFallback() throws {
        let context = try TestSupport.makeInMemoryContext()
        let session = try makeSession(context)

        // 4 × 500 m = 2.0 km, expressed only as a target distance.
        try addBlock(context, to: session, zone: .ga1, distanceKm: nil, reps: 4, targetMetres: 500)
        // Same shape in the recovery zone — must contribute nothing.
        try addBlock(context, to: session, zone: .recovery, distanceKm: nil, reps: 4, targetMetres: 500)

        XCTAssertEqual(SeasonContext.loadKilometers(from: [session]), 2.0, accuracy: 0.0001)
    }

    func testLoadKilometersIsZeroForNoBlocks() throws {
        let context = try TestSupport.makeInMemoryContext()
        let session = try makeSession(context)
        XCTAssertEqual(SeasonContext.loadKilometers(from: [session]), 0.0, accuracy: 0.0001)
    }

    // MARK: - Load counts completed sessions only, inside the season year

    func testCompletedSessionsInYearFiltersStatusAndYear() throws {
        let context = try TestSupport.makeInMemoryContext()

        let completedInYear = try makeSession(context, name: "in-year", date: date(2026, 6, 1))
        let lastDayOfYear = try makeSession(context, name: "dec-31", date: date(2026, 12, 31, 23, 59))
        let firstDayOfNext = try makeSession(context, name: "jan-1", date: date(2027, 1, 1, 0, 0))
        let openInYear = try makeSession(context, name: "open", date: date(2026, 6, 1), status: .open)
        let cancelledInYear = try makeSession(context, name: "cancelled", date: date(2026, 6, 1),
                                              status: .cancelled)

        let result = SeasonContext.completedSessions(
            from: [completedInYear, lastDayOfYear, firstDayOfNext, openInYear, cancelledInYear],
            inYear: 2026,
            calendar: utcCalendar)

        XCTAssertEqual(Set(result.map(\.sessionName)), ["in-year", "dec-31"],
                       "Dec 31 is in the season year, Jan 1 is not; open and cancelled never count")
    }

    func testCompletedSessionsInTrailingWindowIncludesBothBoundaries() throws {
        let context = try TestSupport.makeInMemoryContext()
        let reference = date(2026, 6, 30)
        let windowStart = utcCalendar.date(byAdding: .day, value: -7, to: reference)!

        let onStart = try makeSession(context, name: "on-start", date: windowStart)
        let inside = try makeSession(context, name: "inside", date: date(2026, 6, 27))
        let onReference = try makeSession(context, name: "on-reference", date: reference)
        let beforeWindow = try makeSession(context, name: "before", date: date(2026, 6, 1))
        let future = try makeSession(context, name: "future", date: date(2026, 7, 5))
        let openInside = try makeSession(context, name: "open", date: date(2026, 6, 27), status: .open)

        let result = SeasonContext.completedSessions(
            from: [onStart, inside, onReference, beforeWindow, future, openInside],
            duringLastDays: 7,
            referenceDate: reference,
            calendar: utcCalendar)

        XCTAssertEqual(Set(result.map(\.sessionName)), ["on-start", "inside", "on-reference"],
                       "both boundary instants are inside the window; future and open are not")
    }

    // MARK: - LTAD target table

    /// The CKC-derived table drives the LTAD progress bar on every athlete profile. A transposed
    /// row (U14 and U16 differ by roughly 3×) would misgrade a whole age band invisibly.
    func testLtadKmTargetTable() {
        XCTAssertEqual(SeasonContext.ltadKmTarget(for: "U10").min, 200)
        XCTAssertEqual(SeasonContext.ltadKmTarget(for: "U10").max, 300)
        XCTAssertEqual(SeasonContext.ltadKmTarget(for: "U12").min, 300)
        XCTAssertEqual(SeasonContext.ltadKmTarget(for: "U12").max, 700)
        XCTAssertEqual(SeasonContext.ltadKmTarget(for: "U14").min, 700)
        XCTAssertEqual(SeasonContext.ltadKmTarget(for: "U14").max, 1530)
        XCTAssertEqual(SeasonContext.ltadKmTarget(for: "U16").min, 2000)
        XCTAssertEqual(SeasonContext.ltadKmTarget(for: "U16").max, 3500)
        XCTAssertEqual(SeasonContext.ltadKmTarget(for: "U18").min, 3600)
        XCTAssertEqual(SeasonContext.ltadKmTarget(for: "U18").max, 4000)
    }

    /// Characterizes today's behavior rather than endorsing it: "Senior" *and* the under-5 "N/A"
    /// bucket both fall through to the Senior range, so an under-5's LTAD bar is measured against a
    /// 3600 km target. Intentional for Senior; a product decision worth revisiting for "N/A".
    func testLtadKmTargetFallsThroughToSeniorForUnrecognizedCategories() {
        for category in ["Senior", "N/A"] {
            XCTAssertEqual(SeasonContext.ltadKmTarget(for: category).min, 3600, "\(category)")
            XCTAssertEqual(SeasonContext.ltadKmTarget(for: category).max, 4000, "\(category)")
        }
    }

    // MARK: - Reviewing an old practice never fabricates attendance

    /// Reopening a completed or cancelled session defaults roster newcomers to absent. A regression
    /// marks athletes present at practices they never attended — fabricating practice history and
    /// training load, and flipping their deletion lock.
    ///
    /// The expectation is a literal table, deliberately *not* `status.isOpen ? .present : .absent` —
    /// restating the implementation would make the test agree with any change to it. Switching over
    /// every `SessionStatus` means a newly added case fails to compile here until someone states its
    /// attendance default, rather than silently inheriting `.present`.
    func testDefaultAttendanceStatusIsPresentOnlyForOpenSessions() throws {
        let context = try TestSupport.makeInMemoryContext()

        for status in SessionStatus.allCases {
            let expected: AttendanceStatus
            switch status {
            case .open:      expected = .present
            case .completed: expected = .absent
            case .cancelled: expected = .absent
            }
            let session = try makeSession(context, name: "s-\(status)", status: status)
            XCTAssertEqual(session.defaultAttendanceStatus, expected,
                           "\(status) sessions must default to \(expected)")
        }
    }
}
