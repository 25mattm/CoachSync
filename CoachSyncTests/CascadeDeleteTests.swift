import XCTest
import SwiftData
@testable import CoachSync

/// Coverage for the hand-rolled cascade-delete helpers in `ModelContext+Cascades.swift`.
///
/// CloudKit forbids `.cascade` delete rules, so every relationship uses `.nullify`
/// and these helpers delete child records by hand. A missed relationship orphans
/// data silently, so each test pins a helper against the real relationship graph.
final class CascadeDeleteTests: XCTestCase {

    private func makeAthlete(_ first: String = "Test", _ last: String = "Athlete") -> Athlete {
        Athlete(firstName: first, lastName: last, dateOfBirth: Date(timeIntervalSince1970: 0))
    }

    // MARK: - deleteAthleteCascade

    func testDeleteAthleteCascade_removesEveryChildRecord() throws {
        let context = try TestSupport.makeInMemoryContext()

        let athlete = makeAthlete()
        let team = Team(teamName: "Team")
        let session = CoachSession(sessionName: "Session", scheduledDate: Date(), team: team)
        let block = SessionBlock(blockName: "Block", blockType: .paddleDistance, sortOrder: 0, session: session)
        context.insert(athlete)
        context.insert(team)
        context.insert(session)
        context.insert(block)

        // One record of every relationship the athlete owns.
        context.insert(TeamMembership(athlete: athlete, team: team))
        context.insert(AttendanceRecord(athlete: athlete, session: session))
        context.insert(PerformanceRecord(athlete: athlete, sessionBlock: block, repNumber: 1))
        context.insert(AthleteNote(noteText: "note", athlete: athlete, session: session, sessionBlock: block))
        context.insert(FitnessTestResult(testType: "2k", result: 480, athlete: athlete))
        context.insert(RegattaResult(regattaName: "Regatta", regattaDate: Date(),
                                     eventDistance: 1000, resultTimeMs: 240_000, athlete: athlete))
        let assessment = TechnicalAssessment(athlete: athlete)
        context.insert(assessment)
        context.insert(TechnicalRating(category: "Catch", factor: "Timing", score: 3, assessment: assessment))
        context.insert(HeightRecord(heightCm: 170, athlete: athlete))
        context.insert(DevelopmentNote(text: "journal entry", athlete: athlete))
        context.insert(KTCAssessment(window: "General Prep 1", setupRecoveryScore: 3,
                                     catchScore: 3, propulsionDrawScore: 3, exitScore: 3, athlete: athlete))
        try context.save()

        context.deleteAthleteCascade(athlete)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Athlete>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TeamMembership>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AttendanceRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PerformanceRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AthleteNote>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FitnessTestResult>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RegattaResult>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TechnicalAssessment>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TechnicalRating>()), 0,
                       "Nested TechnicalRating must be deleted via deleteAssessmentCascade")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<HeightRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DevelopmentNote>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<KTCAssessment>()), 0)

        // The team, session and block are not owned by the athlete — they survive.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Team>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CoachSession>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionBlock>()), 1)
    }

    func testDeleteAthleteCascade_withNoChildren_doesNotCrash() throws {
        let context = try TestSupport.makeInMemoryContext()
        let athlete = makeAthlete("Lonely", "Athlete")
        context.insert(athlete)
        try context.save()

        context.deleteAthleteCascade(athlete)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Athlete>()), 0)
    }

    // MARK: - deleteSessionCascade

    func testDeleteSessionCascade_removesBlocksAttendanceAndNotes() throws {
        let context = try TestSupport.makeInMemoryContext()

        let athlete = makeAthlete()
        let session = CoachSession(sessionName: "Session", scheduledDate: Date())
        let block = SessionBlock(blockName: "Block", blockType: .paddleDistance, sortOrder: 0, session: session)
        context.insert(athlete)
        context.insert(session)
        context.insert(block)
        context.insert(PerformanceRecord(athlete: athlete, sessionBlock: block, repNumber: 1))
        context.insert(PerformanceRecord(athlete: athlete, sessionBlock: block, repNumber: 2))
        context.insert(AthleteNote(noteText: "block note", athlete: athlete, session: session, sessionBlock: block))
        context.insert(AthleteNote(noteText: "session note", athlete: athlete, session: session))
        context.insert(AttendanceRecord(athlete: athlete, session: session))
        try context.save()

        context.deleteSessionCascade(session)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CoachSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionBlock>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PerformanceRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AthleteNote>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AttendanceRecord>()), 0)
        // The athlete is not owned by the session — it survives.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Athlete>()), 1)
    }

    // MARK: - deleteBlockCascade

    func testDeleteBlockCascade_removesPerformanceRecordsButPreservesNotes() throws {
        let context = try TestSupport.makeInMemoryContext()

        let athlete = makeAthlete()
        let session = CoachSession(sessionName: "Session", scheduledDate: Date())
        let block = SessionBlock(blockName: "Block", blockType: .paddleDistance, sortOrder: 0, session: session)
        context.insert(athlete)
        context.insert(session)
        context.insert(block)
        context.insert(PerformanceRecord(athlete: athlete, sessionBlock: block, repNumber: 1))
        context.insert(PerformanceRecord(athlete: athlete, sessionBlock: block, repNumber: 2))
        context.insert(PerformanceRecord(athlete: athlete, sessionBlock: block, repNumber: 3))
        context.insert(AthleteNote(noteText: "note", athlete: athlete, session: session, sessionBlock: block))
        try context.save()

        context.deleteBlockCascade(block)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionBlock>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PerformanceRecord>()), 0)
        // Block-anchored notes are recorded history owned by the session — deleting the
        // block preserves them with the anchor nulled (matches the backend's BlockService).
        let survivingNotes = try context.fetch(FetchDescriptor<AthleteNote>())
        XCTAssertEqual(survivingNotes.count, 1)
        XCTAssertNil(survivingNotes.first?.sessionBlock)
        // The parent session and the athlete survive.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CoachSession>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Athlete>()), 1)
    }

    // MARK: - deleteTeamCascade

    func testDeleteTeamCascade_removesMembershipsButKeepsSessions() throws {
        let context = try TestSupport.makeInMemoryContext()

        let athlete = makeAthlete()
        let team = Team(teamName: "Team")
        context.insert(athlete)
        context.insert(team)
        context.insert(TeamMembership(athlete: athlete, team: team))
        context.insert(TeamMembership(athlete: athlete, team: team))
        context.insert(CoachSession(sessionName: "Session 1", scheduledDate: Date(), team: team))
        context.insert(CoachSession(sessionName: "Session 2", scheduledDate: Date(), team: team))
        try context.save()

        context.deleteTeamCascade(team)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Team>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TeamMembership>()), 0)
        // Sessions are intentionally retained so history survives a team deletion.
        let sessions = try context.fetch(FetchDescriptor<CoachSession>())
        XCTAssertEqual(sessions.count, 2)
        XCTAssertTrue(sessions.allSatisfy { $0.team == nil },
                      "Surviving sessions should have their team reference nilled")
    }

    // MARK: - deleteAssessmentCascade

    func testDeleteAssessmentCascade_removesRatings() throws {
        let context = try TestSupport.makeInMemoryContext()

        let athlete = makeAthlete()
        let assessment = TechnicalAssessment(athlete: athlete)
        context.insert(athlete)
        context.insert(assessment)
        context.insert(TechnicalRating(category: "Catch", factor: "Timing", score: 3, assessment: assessment))
        context.insert(TechnicalRating(category: "Exit", factor: "Clean", score: 4, assessment: assessment))
        context.insert(TechnicalRating(category: "Setup", factor: "Posture", score: 5, assessment: assessment))
        try context.save()

        context.deleteAssessmentCascade(assessment)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TechnicalAssessment>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TechnicalRating>()), 0)
        // The athlete is not owned by the assessment — it survives.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Athlete>()), 1)
    }
}

/// Coverage for the two CLAUDE.md deletion guards: completed sessions and
/// athletes with practice history must not be deletable.
final class DeletionGuardTests: XCTestCase {

    // MARK: - Athlete.hasPracticeHistory

    func testHasPracticeHistory_falseForBareAthleteAndMembershipOnly() throws {
        let context = try TestSupport.makeInMemoryContext()

        let bare = Athlete(firstName: "Bare", lastName: "Athlete", dateOfBirth: Date(timeIntervalSince1970: 0))
        context.insert(bare)

        let team = Team(teamName: "Team")
        let rostered = Athlete(firstName: "Rostered", lastName: "Athlete", dateOfBirth: Date(timeIntervalSince1970: 0))
        context.insert(team)
        context.insert(rostered)
        context.insert(TeamMembership(athlete: rostered, team: team))
        try context.save()

        XCTAssertFalse(bare.hasPracticeHistory)
        XCTAssertFalse(rostered.hasPracticeHistory,
                       "A team membership alone is not practice history — the athlete stays deletable")
    }

    func testHasPracticeHistory_trueForEachHistoryRelationship() throws {
        // Each history relationship must independently flag the athlete as
        // non-deletable; a dropped `||` clause would silently allow deletion.
        let attachers: [(relationship: String, attach: (Athlete, ModelContext) -> Void)] = [
            ("attendanceRecords", { athlete, ctx in
                let session = CoachSession(sessionName: "S", scheduledDate: Date())
                ctx.insert(session)
                ctx.insert(AttendanceRecord(athlete: athlete, session: session))
            }),
            ("performanceRecords", { athlete, ctx in
                let session = CoachSession(sessionName: "S", scheduledDate: Date())
                let block = SessionBlock(blockName: "B", blockType: .paddleDistance, sortOrder: 0, session: session)
                ctx.insert(session)
                ctx.insert(block)
                // A recorded result — pending slots with no time deliberately
                // do NOT count (see testHasPracticeHistory_ignoresRosterTrackingArtifacts).
                ctx.insert(PerformanceRecord(athlete: athlete, sessionBlock: block, repNumber: 1,
                                             recordedTimeMs: 95_000, status: .complete))
            }),
            ("notes", { athlete, ctx in
                let session = CoachSession(sessionName: "S", scheduledDate: Date())
                ctx.insert(session)
                ctx.insert(AthleteNote(noteText: "n", athlete: athlete, session: session))
            }),
            ("fitnessTestResults", { athlete, ctx in
                ctx.insert(FitnessTestResult(testType: "2k", result: 480, athlete: athlete))
            }),
            ("regattaResults", { athlete, ctx in
                ctx.insert(RegattaResult(regattaName: "R", regattaDate: Date(),
                                         eventDistance: 1000, resultTimeMs: 240_000, athlete: athlete))
            }),
            ("technicalAssessments", { athlete, ctx in
                ctx.insert(TechnicalAssessment(athlete: athlete))
            }),
            ("heightRecords", { athlete, ctx in
                ctx.insert(HeightRecord(heightCm: 170, athlete: athlete))
            }),
            ("developmentNotes", { athlete, ctx in
                ctx.insert(DevelopmentNote(text: "d", athlete: athlete))
            }),
            ("ktcAssessments", { athlete, ctx in
                ctx.insert(KTCAssessment(window: "GP1", setupRecoveryScore: 3, catchScore: 3,
                                         propulsionDrawScore: 3, exitScore: 3, athlete: athlete))
            })
        ]

        for entry in attachers {
            let context = try TestSupport.makeInMemoryContext()
            let athlete = Athlete(firstName: "A", lastName: "B", dateOfBirth: Date(timeIntervalSince1970: 0))
            context.insert(athlete)
            entry.attach(athlete, context)
            try context.save()
            XCTAssertTrue(athlete.hasPracticeHistory,
                          "\(entry.relationship) must count as practice history")
        }
    }

    func testHasPracticeHistory_ignoresRosterTrackingArtifacts() throws {
        // An absent/excused attendance mark or an unfilled pre-generated rep
        // slot is roster bookkeeping, not practice history — an athlete who
        // never actually attended must stay deletable.
        let context = try TestSupport.makeInMemoryContext()
        let athlete = Athlete(firstName: "A", lastName: "B", dateOfBirth: Date(timeIntervalSince1970: 0))
        let session = CoachSession(sessionName: "S", scheduledDate: Date())
        let block = SessionBlock(blockName: "B", blockType: .paddleDistance, sortOrder: 0, session: session)
        context.insert(athlete)
        context.insert(session)
        context.insert(block)
        context.insert(AttendanceRecord(athlete: athlete, session: session, status: .absent))
        context.insert(AttendanceRecord(athlete: athlete, session: session, status: .excused))
        context.insert(PerformanceRecord(athlete: athlete, sessionBlock: block, repNumber: 1)) // pending, no time
        try context.save()

        XCTAssertFalse(athlete.hasPracticeHistory)
    }

    func testHasPracticeHistory_countsPresentAttendanceAndDNSMarks() throws {
        // Present attendance and DNS/DNF marks are deliberate coach-recorded
        // outcomes — each must independently lock the athlete.
        let context = try TestSupport.makeInMemoryContext()

        let attendee = Athlete(firstName: "Was", lastName: "There", dateOfBirth: Date(timeIntervalSince1970: 0))
        let racer = Athlete(firstName: "Did", lastName: "NotStart", dateOfBirth: Date(timeIntervalSince1970: 0))
        let session = CoachSession(sessionName: "S", scheduledDate: Date())
        let block = SessionBlock(blockName: "B", blockType: .paddleDistance, sortOrder: 0, session: session)
        context.insert(attendee)
        context.insert(racer)
        context.insert(session)
        context.insert(block)
        context.insert(AttendanceRecord(athlete: attendee, session: session, status: .present))
        context.insert(PerformanceRecord(athlete: racer, sessionBlock: block, repNumber: 1, status: .dns))
        try context.save()

        XCTAssertTrue(attendee.hasPracticeHistory)
        XCTAssertTrue(racer.hasPracticeHistory)
    }

    // MARK: - CoachSession.isDeletable

    func testIsDeletable_falseOnlyForCompletedSessions() {
        let session = CoachSession(sessionName: "S", scheduledDate: Date())

        session.status = .completed
        XCTAssertFalse(session.isDeletable, "Completed sessions cannot be deleted")

        for status in [SessionStatus.open, .cancelled] {
            session.status = status
            XCTAssertTrue(session.isDeletable, "\(status) sessions may be deleted")
        }
    }

}

/// Coverage for the `SessionStatus` redesign: the tolerant `RawRepresentable`
/// decoder that folds legacy raw values to `.open`, the v1.1 wire-compatible
/// raw strings, the `Codable` path, and `isOpen`.
final class SessionStatusTests: XCTestCase {

    // MARK: - isOpen

    func testIsOpen() {
        XCTAssertTrue(SessionStatus.open.isOpen)
        XCTAssertFalse(SessionStatus.completed.isOpen)
        XCTAssertFalse(SessionStatus.cancelled.isOpen)
    }

    // MARK: - RawRepresentable (tolerant decode)

    func testRawValue_legacyValuesFoldToOpen() {
        // Pre-redesign local stores and any un-updated v1.1 device still hold
        // or write these strings; they must decode to `.open`.
        XCTAssertEqual(SessionStatus(rawValue: "Scheduled"), .open)
        XCTAssertEqual(SessionStatus(rawValue: "In Progress"), .open)
    }

    func testRawValue_currentValues() {
        XCTAssertEqual(SessionStatus(rawValue: "Completed"), .completed)
        XCTAssertEqual(SessionStatus(rawValue: "Cancelled"), .cancelled)
    }

    func testRawValue_unknownFoldsToOpen() {
        // `init(rawValue:)` is total — no input produces a decode failure.
        XCTAssertEqual(SessionStatus(rawValue: "garbage"), .open)
        XCTAssertEqual(SessionStatus(rawValue: ""), .open)
    }

    func testRawValue_roundTrips() {
        for status in SessionStatus.allCases {
            XCTAssertEqual(SessionStatus(rawValue: status.rawValue), status)
        }
    }

    func testRawValue_openIsWireCompatibleWithV11() {
        // `.open` must encode as "Scheduled" so records this build writes stay
        // decodable by a shipped v1.1 build — do not "fix" this to "Open".
        XCTAssertEqual(SessionStatus.open.rawValue, "Scheduled")
        XCTAssertEqual(SessionStatus.completed.rawValue, "Completed")
        XCTAssertEqual(SessionStatus.cancelled.rawValue, "Cancelled")
    }

    // MARK: - Codable (tolerant decode)

    private struct StatusBox: Codable {
        var status: SessionStatus
    }

    func testCodable_roundTrips() throws {
        for status in SessionStatus.allCases {
            let data = try JSONEncoder().encode(StatusBox(status: status))
            XCTAssertEqual(try JSONDecoder().decode(StatusBox.self, from: data).status, status)
        }
    }

    func testCodable_legacyValuesDecodeToOpen() throws {
        let scheduled = try JSONDecoder().decode(StatusBox.self, from: Data(#"{"status":"Scheduled"}"#.utf8))
        let inProgress = try JSONDecoder().decode(StatusBox.self, from: Data(#"{"status":"In Progress"}"#.utf8))
        XCTAssertEqual(scheduled.status, .open)
        XCTAssertEqual(inProgress.status, .open)
    }
}

/// Covers `@Model` computed properties that drive load math, time display, and
/// roster filtering — previously untested (May-2026 review P4-L2 / P4-L3).
final class ModelComputedPropertyTests: XCTestCase {

    // MARK: - SessionBlock.effectiveDistanceKm

    func testEffectiveDistanceKm_prefersExplicitDistanceKm() throws {
        let context = try TestSupport.makeInMemoryContext()
        let session = CoachSession(sessionName: "S", scheduledDate: Date())
        context.insert(session)
        let block = SessionBlock(blockName: "B", blockType: .paddleDistance,
                                 sortOrder: 0, repetitionCount: 4, session: session,
                                 distanceKm: 1.5)
        context.insert(block)
        XCTAssertEqual(block.effectiveDistanceKm, 1.5)
    }

    func testEffectiveDistanceKm_derivesFromRepsAndMetres() throws {
        let context = try TestSupport.makeInMemoryContext()
        let session = CoachSession(sessionName: "S", scheduledDate: Date())
        context.insert(session)
        let block = SessionBlock(blockName: "B", blockType: .paddleDistance,
                                 sortOrder: 0, repetitionCount: 3, session: session)
        block.targetDistanceMetres = 500
        context.insert(block)
        // 3 reps × 500 m = 1.5 km
        XCTAssertEqual(block.effectiveDistanceKm ?? 0, 1.5, accuracy: 0.0001)
    }

    func testEffectiveDistanceKm_nilWhenNoDistance() throws {
        let context = try TestSupport.makeInMemoryContext()
        let session = CoachSession(sessionName: "S", scheduledDate: Date())
        context.insert(session)
        let block = SessionBlock(blockName: "B", blockType: .technique,
                                 sortOrder: 0, session: session)
        context.insert(block)
        XCTAssertNil(block.effectiveDistanceKm)
    }

    // MARK: - PerformanceRecord.formattedTime

    func testFormattedTime_completeWithTime() throws {
        let record = try makeRecord(status: .complete, ms: 105_000)
        XCTAssertEqual(record.formattedTime, formatMillisecondsForDisplay(105_000))
    }

    func testFormattedTime_dnsAndDnf() throws {
        XCTAssertEqual(try makeRecord(status: .dns, ms: nil).formattedTime, "DNS")
        XCTAssertEqual(try makeRecord(status: .dnf, ms: nil).formattedTime, "DNF")
    }

    func testFormattedTime_pendingIsNil() throws {
        XCTAssertNil(try makeRecord(status: .pending, ms: nil).formattedTime)
    }

    func testFormattedTime_completeWithoutTimeShowsSentinel() throws {
        // Latent invariant violation (the logger only marks .complete with a
        // time) — should surface a visible sentinel, never a blank (review P1-L3).
        XCTAssertEqual(try makeRecord(status: .complete, ms: nil).formattedTime, "—")
    }

    private func makeRecord(status: RepEntryStatus, ms: Int?) throws -> PerformanceRecord {
        let context = try TestSupport.makeInMemoryContext()
        let athlete = Athlete(firstName: "A", lastName: "B", dateOfBirth: Date(timeIntervalSince1970: 0))
        let session = CoachSession(sessionName: "S", scheduledDate: Date())
        let block = SessionBlock(blockName: "B", blockType: .paddleDistance, sortOrder: 0, session: session)
        context.insert(athlete); context.insert(session); context.insert(block)
        let record = PerformanceRecord(athlete: athlete, sessionBlock: block, repNumber: 1,
                                       recordedTimeMs: ms, status: status)
        context.insert(record)
        return record
    }

    // MARK: - Team.activeMembers

    func testActiveMembers_excludesInactiveAthletesAndLeftMembers() throws {
        let context = try TestSupport.makeInMemoryContext()
        let team = Team(teamName: "T")
        context.insert(team)

        let active = Athlete(firstName: "Act", lastName: "Ive", dateOfBirth: Date(timeIntervalSince1970: 0))
        let inactive = Athlete(firstName: "In", lastName: "Active", dateOfBirth: Date(timeIntervalSince1970: 0))
        inactive.isActive = false
        let left = Athlete(firstName: "Le", lastName: "Ft", dateOfBirth: Date(timeIntervalSince1970: 0))
        for athlete in [active, inactive, left] { context.insert(athlete) }

        context.insert(TeamMembership(athlete: active, team: team))
        context.insert(TeamMembership(athlete: inactive, team: team))
        let leftMembership = TeamMembership(athlete: left, team: team)
        leftMembership.leftDate = Date(timeIntervalSince1970: 1_000)
        context.insert(leftMembership)
        try context.save()

        // Only the active, still-on-the-roster athlete qualifies.
        XCTAssertEqual(team.activeMembers.map(\.firstName), ["Act"])
    }
}

/// Verifies development-coverage matching succeeds via the rating's CATEGORY,
/// not only its factor name — the category-themed predefined tags
/// (catch/exit/draw/balance/…) must cover factors whose names lack the tag word
/// (May-2026 review P2 follow-up).
final class DevelopmentCoverageCategoryTests: XCTestCase {
    func testDevelopmentCoverage_matchesViaCategory() throws {
        let context = try TestSupport.makeInMemoryContext()
        let athlete = Athlete(firstName: "A", lastName: "B", dateOfBirth: Date(timeIntervalSince1970: 0))
        context.insert(athlete)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let assessment = TechnicalAssessment(date: date, athlete: athlete)
        context.insert(assessment)
        // Factor name contains no predefined tag word; its category does.
        context.insert(TechnicalRating(category: "Balance Set-Up",
                                       factor: "Position and posture in boat",
                                       score: 2, assessment: assessment))
        // "#balance" is a substring of the category "Balance Set-Up", not the factor.
        context.insert(DevelopmentNote(date: date, text: "Balance set-up drills",
                                       tags: ["balance"], athlete: athlete))
        try context.save()

        let coverage = athlete.developmentCoverage(referenceDate: date)
        XCTAssertEqual(coverage.count, 1)
        XCTAssertEqual(coverage.first?.noteCount, 1,
                       "A #balance note should cover a Balance Set-Up factor via category match")
        XCTAssertEqual(coverage.first?.isCovered, true)
    }
}
