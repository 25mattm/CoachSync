import XCTest
import SwiftData
@testable import CoachSync

/// Unit tests for the insight signals — the math primitives plus the `Athlete`
/// extension signals that drive the coach-facing alerts. The model-backed
/// signal tests use an in-memory `ModelContainer` via `TestSupport`.
final class InsightSignalsTests: XCTestCase {

    // MARK: - leastSquaresSlope

    func testLeastSquaresSlope_evenlyIncreasing() {
        // y = 10x → slope = 10
        let slope = leastSquaresSlope([10, 20, 30])
        XCTAssertNotNil(slope)
        XCTAssertEqual(slope!, 10.0, accuracy: 1e-6)
    }

    func testLeastSquaresSlope_evenlyDecreasing() {
        // y = -5x + 100 → slope = -5
        let slope = leastSquaresSlope([100, 95, 90, 85])
        XCTAssertNotNil(slope)
        XCTAssertEqual(slope!, -5.0, accuracy: 1e-6)
    }

    func testLeastSquaresSlope_constant() {
        let slope = leastSquaresSlope([5, 5, 5, 5])
        XCTAssertNotNil(slope)
        XCTAssertEqual(slope!, 0.0, accuracy: 1e-6)
    }

    func testLeastSquaresSlope_fewerThanTwoPoints_returnsNil() {
        // Slope is undefined without at least two points to fit a line through.
        XCTAssertNil(leastSquaresSlope([]))
        XCTAssertNil(leastSquaresSlope([42]))
    }

    // MARK: - coefficientOfVariation

    func testCoefficientOfVariation_uniformValues_returnsZero() {
        let cv = coefficientOfVariation([100, 100, 100, 100])
        XCTAssertNotNil(cv)
        XCTAssertEqual(cv!, 0.0, accuracy: 1e-6)
    }

    func testCoefficientOfVariation_knownDistribution() {
        // [9, 10, 11] → mean = 10, variance = 2/3, stddev = √(2/3)
        // CV = √(2/3) / 10
        let cv = coefficientOfVariation([9, 10, 11])
        XCTAssertNotNil(cv)
        XCTAssertEqual(cv!, (2.0 / 3.0).squareRoot() / 10.0, accuracy: 1e-6)
    }

    func testCoefficientOfVariation_nonPositiveMean_returnsNil() {
        // CV is undefined when the mean is zero or negative.
        XCTAssertNil(coefficientOfVariation([-1, 1, -1, 1]))   // mean = 0
        XCTAssertNil(coefficientOfVariation([-10, -20, -30])) // mean < 0
    }

    func testCoefficientOfVariation_singleValue_returnsNil() {
        XCTAssertNil(coefficientOfVariation([100]))
    }

    // MARK: - InsightThresholds sanity

    func testInsightThresholds_haveExpectedSigns() {
        // Locks in the directional contract: declining = positive slope (slower),
        // improving = negative slope (faster). Catches accidental sign flips.
        XCTAssertGreaterThan(InsightThresholds.decliningSlopeMs, 0)
        XCTAssertLessThan(InsightThresholds.improvingSlopeMs, 0)
        XCTAssertGreaterThan(InsightThresholds.pacingCVAlert, 0)
        XCTAssertGreaterThanOrEqual(InsightThresholds.minPointsForRegression, 2)
        XCTAssertGreaterThanOrEqual(InsightThresholds.minPointsForCV, 2)
    }

    // MARK: - Athlete.decliningBlockName / mostImprovedBlockName

    func testDecliningBlockName_flagsSlowingBlock() throws {
        let context = try TestSupport.makeInMemoryContext()
        let athlete = Athlete(firstName: "A", lastName: "B", dateOfBirth: Date(timeIntervalSince1970: 0))
        context.insert(athlete)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let day: TimeInterval = 86_400
        addTimedBlock(name: "500m TT", time: 120_000, date: base, athlete: athlete, context: context)
        addTimedBlock(name: "500m TT", time: 124_000, date: base + day, athlete: athlete, context: context)
        addTimedBlock(name: "500m TT", time: 128_000, date: base + 2 * day, athlete: athlete, context: context)
        try context.save()

        XCTAssertEqual(athlete.decliningBlockName, "500m TT")
        XCTAssertNil(athlete.mostImprovedBlockName)
    }

    func testMostImprovedBlockName_flagsImprovingBlock() throws {
        let context = try TestSupport.makeInMemoryContext()
        let athlete = Athlete(firstName: "A", lastName: "B", dateOfBirth: Date(timeIntervalSince1970: 0))
        context.insert(athlete)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let day: TimeInterval = 86_400
        addTimedBlock(name: "500m TT", time: 128_000, date: base, athlete: athlete, context: context)
        addTimedBlock(name: "500m TT", time: 124_000, date: base + day, athlete: athlete, context: context)
        addTimedBlock(name: "500m TT", time: 120_000, date: base + 2 * day, athlete: athlete, context: context)
        try context.save()

        XCTAssertEqual(athlete.mostImprovedBlockName, "500m TT")
        XCTAssertNil(athlete.decliningBlockName)
    }

    func testRegressedBlockName_nilBelowThreeRecords() throws {
        // Two records is below `minPointsForRegression` — no signal yet.
        let context = try TestSupport.makeInMemoryContext()
        let athlete = Athlete(firstName: "A", lastName: "B", dateOfBirth: Date(timeIntervalSince1970: 0))
        context.insert(athlete)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        addTimedBlock(name: "500m TT", time: 120_000, date: base, athlete: athlete, context: context)
        addTimedBlock(name: "500m TT", time: 130_000, date: base + 86_400, athlete: athlete, context: context)
        try context.save()

        XCTAssertNil(athlete.decliningBlockName)
        XCTAssertNil(athlete.mostImprovedBlockName)
    }

    func testRegressedBlockName_ignoresIncompleteRecords() throws {
        // Three records exist, but one is still pending — only two are valid,
        // which is below the regression threshold, so no signal fires.
        let context = try TestSupport.makeInMemoryContext()
        let athlete = Athlete(firstName: "A", lastName: "B", dateOfBirth: Date(timeIntervalSince1970: 0))
        context.insert(athlete)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let day: TimeInterval = 86_400
        addTimedBlock(name: "500m TT", time: 120_000, date: base, athlete: athlete, context: context)
        addTimedBlock(name: "500m TT", time: 124_000, date: base + day, athlete: athlete, context: context)
        addTimedBlock(name: "500m TT", time: 128_000, date: base + 2 * day,
                      status: .pending, athlete: athlete, context: context)
        try context.save()

        XCTAssertNil(athlete.decliningBlockName)
    }

    // MARK: - Athlete.inconsistentPacingBlock

    func testInconsistentPacingBlock_flagsHighRepVariance() throws {
        let context = try TestSupport.makeInMemoryContext()
        let athlete = Athlete(firstName: "A", lastName: "B", dateOfBirth: Date(timeIntervalSince1970: 0))
        context.insert(athlete)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // The same block in two sessions, each with widely varying rep times.
        addPacingBlock(name: "Pyramid", repTimes: [100_000, 140_000, 100_000, 140_000],
                       date: base, athlete: athlete, context: context)
        addPacingBlock(name: "Pyramid", repTimes: [100_000, 140_000, 100_000, 140_000],
                       date: base + 86_400, athlete: athlete, context: context)
        try context.save()

        XCTAssertEqual(athlete.inconsistentPacingBlock?.name, "Pyramid")
    }

    func testInconsistentPacingBlock_nilForConsistentPacing() throws {
        let context = try TestSupport.makeInMemoryContext()
        let athlete = Athlete(firstName: "A", lastName: "B", dateOfBirth: Date(timeIntervalSince1970: 0))
        context.insert(athlete)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        addPacingBlock(name: "Pyramid", repTimes: [120_000, 120_000, 120_000, 120_000],
                       date: base, athlete: athlete, context: context)
        addPacingBlock(name: "Pyramid", repTimes: [120_000, 120_000, 120_000, 120_000],
                       date: base + 86_400, athlete: athlete, context: context)
        try context.save()

        XCTAssertNil(athlete.inconsistentPacingBlock)
    }

    // MARK: - Athlete.ktcDecliningCount

    func testKtcDecliningCount_returnsCountWhenScoresTrendDown() throws {
        let context = try TestSupport.makeInMemoryContext()
        let athlete = Athlete(firstName: "A", lastName: "B", dateOfBirth: Date(timeIntervalSince1970: 0))
        context.insert(athlete)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for (index, score) in [5, 4, 3].enumerated() {
            context.insert(KTCAssessment(
                date: base + Double(index) * 86_400,
                window: "Window \(index)",
                setupRecoveryScore: score, catchScore: score,
                propulsionDrawScore: score, exitScore: score,
                athlete: athlete
            ))
        }
        try context.save()

        XCTAssertEqual(athlete.ktcDecliningCount, 3)
    }

    func testKtcDecliningCount_nilWhenImproving() throws {
        let context = try TestSupport.makeInMemoryContext()
        let athlete = Athlete(firstName: "A", lastName: "B", dateOfBirth: Date(timeIntervalSince1970: 0))
        context.insert(athlete)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for (index, score) in [3, 4, 5].enumerated() {
            context.insert(KTCAssessment(
                date: base + Double(index) * 86_400,
                window: "Window \(index)",
                setupRecoveryScore: score, catchScore: score,
                propulsionDrawScore: score, exitScore: score,
                athlete: athlete
            ))
        }
        try context.save()

        XCTAssertNil(athlete.ktcDecliningCount)
    }

    // MARK: - Athlete.developmentCoverage

    func testDevelopmentCoverage_noAssessment_returnsEmpty() throws {
        let context = try TestSupport.makeInMemoryContext()
        let athlete = Athlete(firstName: "A", lastName: "B", dateOfBirth: Date(timeIntervalSince1970: 0))
        context.insert(athlete)
        try context.save()

        XCTAssertTrue(athlete.developmentCoverage().isEmpty)
    }

    func testDevelopmentCoverage_focusAreaCovered_returnsNoteCount() throws {
        let context = try TestSupport.makeInMemoryContext()
        let athlete = Athlete(firstName: "A", lastName: "B", dateOfBirth: Date(timeIntervalSince1970: 0))
        context.insert(athlete)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let assessment = TechnicalAssessment(date: date, athlete: athlete)
        context.insert(assessment)
        context.insert(TechnicalRating(category: "Stroke", factor: "Catch timing",
                                       score: 2, assessment: assessment))
        // Two notes inside the default 60-day window, both tagged "catch".
        context.insert(DevelopmentNote(date: date, text: "Drilled the catch",
                                       tags: ["catch"], athlete: athlete))
        context.insert(DevelopmentNote(date: date, text: "Catch reset",
                                       tags: ["catch", "drill"], athlete: athlete))
        try context.save()

        let coverage = athlete.developmentCoverage(referenceDate: date)
        XCTAssertEqual(coverage.count, 1)
        XCTAssertEqual(coverage.first?.noteCount, 2)
        XCTAssertEqual(coverage.first?.isCovered, true)
    }

    func testDevelopmentCoverage_focusAreaUncovered_flagsGap() throws {
        let context = try TestSupport.makeInMemoryContext()
        let athlete = Athlete(firstName: "A", lastName: "B", dateOfBirth: Date(timeIntervalSince1970: 0))
        context.insert(athlete)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let assessment = TechnicalAssessment(date: date, athlete: athlete)
        context.insert(assessment)
        context.insert(TechnicalRating(category: "Stroke", factor: "Exit timing",
                                       score: 1, assessment: assessment))
        // No matching notes at all.
        try context.save()

        let coverage = athlete.developmentCoverage(referenceDate: date)
        XCTAssertEqual(coverage.count, 1)
        XCTAssertEqual(coverage.first?.noteCount, 0)
        XCTAssertEqual(coverage.first?.isCovered, false)
    }

    func testDevelopmentCoverage_noteOutsideWindow_ignored() throws {
        let context = try TestSupport.makeInMemoryContext()
        let athlete = Athlete(firstName: "A", lastName: "B", dateOfBirth: Date(timeIntervalSince1970: 0))
        context.insert(athlete)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let assessment = TechnicalAssessment(date: date, athlete: athlete)
        context.insert(assessment)
        context.insert(TechnicalRating(category: "Stroke", factor: "Catch timing",
                                       score: 2, assessment: assessment))
        // Note dated 90 days before the reference — outside the default 60-day window.
        let staleNote = date.addingTimeInterval(-90 * 86_400)
        context.insert(DevelopmentNote(date: staleNote, text: "Old catch drill",
                                       tags: ["catch"], athlete: athlete))
        try context.save()

        XCTAssertEqual(athlete.developmentCoverage(referenceDate: date).first?.noteCount, 0,
                       "Notes outside the 60-day window are not counted")
    }

    func testDevelopmentCoverage_matchingIsCaseInsensitive() throws {
        let context = try TestSupport.makeInMemoryContext()
        let athlete = Athlete(firstName: "A", lastName: "B", dateOfBirth: Date(timeIntervalSince1970: 0))
        context.insert(athlete)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let assessment = TechnicalAssessment(date: date, athlete: athlete)
        context.insert(assessment)
        // Factor uses uppercase; tag is lowercase. Substring match must be case-insensitive.
        context.insert(TechnicalRating(category: "Stroke", factor: "EXIT cleanliness",
                                       score: 2, assessment: assessment))
        context.insert(DevelopmentNote(date: date, text: "Exit drill",
                                       tags: ["exit"], athlete: athlete))
        try context.save()

        XCTAssertEqual(athlete.developmentCoverage(referenceDate: date).first?.noteCount, 1)
    }

    func testDevelopmentCoverage_nonTechnicalTagsDontFalseMatch() throws {
        let context = try TestSupport.makeInMemoryContext()
        let athlete = Athlete(firstName: "A", lastName: "B", dateOfBirth: Date(timeIntervalSince1970: 0))
        context.insert(athlete)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let assessment = TechnicalAssessment(date: date, athlete: athlete)
        context.insert(assessment)
        context.insert(TechnicalRating(category: "Stroke", factor: "Catch timing",
                                       score: 2, assessment: assessment))
        // Note exists in window, but tagged only with non-technical tags — should
        // NOT match the "Catch timing" factor.
        context.insert(DevelopmentNote(date: date, text: "Race-day jitters",
                                       tags: ["mental", "race-prep"], athlete: athlete))
        try context.save()

        XCTAssertEqual(athlete.developmentCoverage(referenceDate: date).first?.noteCount, 0)
    }

    func testDevelopmentCoverage_strengthsExcluded() throws {
        let context = try TestSupport.makeInMemoryContext()
        let athlete = Athlete(firstName: "A", lastName: "B", dateOfBirth: Date(timeIntervalSince1970: 0))
        context.insert(athlete)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let assessment = TechnicalAssessment(date: date, athlete: athlete)
        context.insert(assessment)
        // Two ratings: a score-1 focus area (should appear) and a score-4 strength
        // (should not).
        context.insert(TechnicalRating(category: "Stroke", factor: "Catch timing",
                                       score: 1, assessment: assessment))
        context.insert(TechnicalRating(category: "Stroke", factor: "Boat balance",
                                       score: 4, assessment: assessment))
        try context.save()

        let coverage = athlete.developmentCoverage(referenceDate: date)
        XCTAssertEqual(coverage.count, 1, "Strengths (score ≥ 4) must not appear in coverage")
        XCTAssertEqual(coverage.first?.rating.factor, "Catch timing")
    }

    // MARK: - Model-backed test helpers

    /// Inserts a `name` block into a fresh session dated `date`, with one
    /// `PerformanceRecord` for `athlete` at `time` ms and the given status.
    private func addTimedBlock(name: String, time: Int, date: Date,
                               status: RepEntryStatus = .complete,
                               athlete: Athlete, context: ModelContext) {
        let session = CoachSession(sessionName: "Session", scheduledDate: date)
        let block = SessionBlock(blockName: name, blockType: .paddleTimePieces,
                                 sortOrder: 0, session: session)
        let record = PerformanceRecord(athlete: athlete, sessionBlock: block,
                                       repNumber: 1, recordedTimeMs: time, status: status)
        context.insert(session)
        context.insert(block)
        context.insert(record)
    }

    /// Inserts a `name` block into a fresh session dated `date`, with one
    /// completed `PerformanceRecord` per entry in `repTimes`.
    private func addPacingBlock(name: String, repTimes: [Int], date: Date,
                                athlete: Athlete, context: ModelContext) {
        let session = CoachSession(sessionName: "Session", scheduledDate: date)
        let block = SessionBlock(blockName: name, blockType: .paddlePyramid,
                                 sortOrder: 0, session: session)
        context.insert(session)
        context.insert(block)
        for (index, time) in repTimes.enumerated() {
            context.insert(PerformanceRecord(athlete: athlete, sessionBlock: block,
                                             repNumber: index + 1, recordedTimeMs: time,
                                             status: .complete))
        }
    }
}
