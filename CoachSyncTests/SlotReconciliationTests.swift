import XCTest
import SwiftData
@testable import CoachSync

/// Coverage for slot reconciliation when a block edit changes rep capacity.
///
/// Shrinking a block used to strand `PerformanceRecord` slots beyond the new
/// rep count, where the logger no longer rendered them but analytics still
/// counted them. The fix has two halves, pinned here along with the shared
/// type rule:
/// - `SessionBlock.highestFilledRepNumber` — what `AddBlockSheet`'s guard
///   compares against the planned capacity before refusing a save that would
///   strand recorded results.
/// - `ModelContext.pruneUnfilledSlots(of:beyondRep:)` — deletes unfilled
///   orphans past the new capacity, and must never touch a slot holding
///   coach-recorded data (a time, DNS, or DNF).
final class SlotReconciliationTests: XCTestCase {

    // MARK: - Fixtures

    private func makeContextAndBlock(
        reps: Int
    ) throws -> (context: ModelContext, block: SessionBlock, athlete: Athlete) {
        let context = try TestSupport.makeInMemoryContext()
        let athlete = Athlete(firstName: "Test", lastName: "Athlete",
                              dateOfBirth: Date(timeIntervalSince1970: 0))
        let session = CoachSession(sessionName: "Practice", scheduledDate: Date())
        let block = SessionBlock(blockName: "4 × 500m", blockType: .paddleDistance,
                                 sortOrder: 0, repetitionCount: reps, session: session)
        context.insert(athlete)
        context.insert(session)
        context.insert(block)
        return (context, block, athlete)
    }

    @discardableResult
    private func addSlot(
        _ context: ModelContext, block: SessionBlock, athlete: Athlete,
        rep: Int, timeMs: Int? = nil, status: RepEntryStatus = .pending
    ) -> PerformanceRecord {
        let slot = PerformanceRecord(athlete: athlete, sessionBlock: block,
                                     repNumber: rep, recordedTimeMs: timeMs,
                                     status: status)
        context.insert(slot)
        return slot
    }

    private func repNumbers(of block: SessionBlock) -> Set<Int> {
        Set((block.performanceRecords ?? []).map(\.repNumber))
    }

    // MARK: - highestFilledRepNumber (the shrink guard's input)

    func testHighestFilledRep_countsTimesAndDeliberateDNSMarks() throws {
        let (context, block, athlete) = try makeContextAndBlock(reps: 6)
        addSlot(context, block: block, athlete: athlete, rep: 1, timeMs: 125_000, status: .complete)
        // DNS carries no time but is a deliberate race-piece outcome — it must
        // count as filled, exactly as it does for Athlete.hasPracticeHistory.
        addSlot(context, block: block, athlete: athlete, rep: 2, status: .dns)
        for rep in 3...6 {
            addSlot(context, block: block, athlete: athlete, rep: rep)
        }
        try context.save()

        XCTAssertEqual(block.highestFilledRepNumber, 2)
    }

    func testHighestFilledRep_isZeroForPendingOnlyAndEmptyBlocks() throws {
        let (context, block, athlete) = try makeContextAndBlock(reps: 4)
        XCTAssertEqual(block.highestFilledRepNumber, 0, "No slots at all → 0")

        for rep in 1...4 {
            addSlot(context, block: block, athlete: athlete, rep: rep)
        }
        try context.save()

        XCTAssertEqual(block.highestFilledRepNumber, 0,
                       "Pending slots with no time are roster artifacts, not data")
    }

    // MARK: - Shrink

    func testShrink_prunesPendingOrphansAndKeepsFilledReps() throws {
        let (context, block, athlete) = try makeContextAndBlock(reps: 6)
        let timed = addSlot(context, block: block, athlete: athlete,
                            rep: 1, timeMs: 125_000, status: .complete)
        let dns = addSlot(context, block: block, athlete: athlete, rep: 2, status: .dns)
        addSlot(context, block: block, athlete: athlete, rep: 3)
        for rep in 4...6 {
            addSlot(context, block: block, athlete: athlete, rep: rep)
        }
        try context.save()

        // Coach shrinks 6 → 3. Guard allows it (highest filled is 2).
        XCTAssertLessThanOrEqual(block.highestFilledRepNumber, 3)
        let deleted = context.pruneUnfilledSlots(of: block, beyondRep: 3)
        try context.save()

        XCTAssertEqual(deleted, 3, "Reps 4–6 were pending orphans")
        XCTAssertEqual(repNumbers(of: block), [1, 2, 3])
        XCTAssertEqual(timed.recordedTimeMs, 125_000, "Recorded time untouched")
        XCTAssertEqual(dns.status, .dns, "DNS mark untouched")
    }

    func testShrinkBelowFilledRep_isDetectedAndPruneStillProtectsData() throws {
        let (context, block, athlete) = try makeContextAndBlock(reps: 6)
        addSlot(context, block: block, athlete: athlete, rep: 1, timeMs: 120_000, status: .complete)
        for rep in 2...4 {
            addSlot(context, block: block, athlete: athlete, rep: rep)
        }
        addSlot(context, block: block, athlete: athlete, rep: 5, status: .dnf)
        addSlot(context, block: block, athlete: athlete, rep: 6)
        try context.save()

        // Coach tries 6 → 3: AddBlockSheet's guard condition (highest filled
        // rep exceeds the requested capacity of 3) must fire — the DNF on
        // rep 5 outranks the shrink and the save is refused before anything
        // mutates.
        XCTAssertEqual(block.highestFilledRepNumber, 5)

        // Defense in depth: even if pruning ran with the too-small capacity,
        // it must only remove unfilled orphans — never the DNF.
        let deleted = context.pruneUnfilledSlots(of: block, beyondRep: 3)
        try context.save()

        XCTAssertEqual(deleted, 2, "Only pending reps 4 and 6 are prunable")
        XCTAssertEqual(repNumbers(of: block), [1, 2, 3, 5])
        XCTAssertEqual(block.highestFilledRepNumber, 5, "DNF survived")
    }

    // MARK: - Grow

    func testGrow_deletesNothing() throws {
        let (context, block, athlete) = try makeContextAndBlock(reps: 4)
        addSlot(context, block: block, athlete: athlete, rep: 1, timeMs: 130_000, status: .complete)
        for rep in 2...4 {
            addSlot(context, block: block, athlete: athlete, rep: rep)
        }
        try context.save()

        // Coach grows 4 → 10. No orphans exist; missing slots are the logger
        // backfill's job, not reconciliation's.
        let deleted = context.pruneUnfilledSlots(of: block, beyondRep: 10)
        try context.save()

        XCTAssertEqual(deleted, 0)
        XCTAssertEqual(repNumbers(of: block), [1, 2, 3, 4])
    }

    // MARK: - Shrink then regrow

    func testShrinkThenRegrow_filledSurviveAndPendingComeBackFresh() throws {
        let (context, block, athlete) = try makeContextAndBlock(reps: 6)
        for rep in 1...3 {
            addSlot(context, block: block, athlete: athlete,
                    rep: rep, timeMs: 100_000 + rep, status: .complete)
        }
        for rep in 4...6 {
            addSlot(context, block: block, athlete: athlete, rep: rep)
        }
        try context.save()

        let filledIDs = Set((block.performanceRecords ?? [])
            .filter { $0.status == .complete }.map(\.id))

        // Shrink 6 → 3.
        context.pruneUnfilledSlots(of: block, beyondRep: 3)
        block.repetitionCount = 3
        try context.save()
        XCTAssertEqual(repNumbers(of: block), [1, 2, 3])

        // Regrow 3 → 6: prune is a no-op, then the logger's backfill creates
        // the missing slots as fresh pending (mirrored here — same insert the
        // logger performs for a present athlete × missing rep).
        block.repetitionCount = 6
        XCTAssertEqual(context.pruneUnfilledSlots(of: block, beyondRep: 6), 0)
        for rep in 1...6 where !repNumbers(of: block).contains(rep) {
            addSlot(context, block: block, athlete: athlete, rep: rep)
        }
        try context.save()

        XCTAssertEqual(repNumbers(of: block), [1, 2, 3, 4, 5, 6])
        let survivors = Set((block.performanceRecords ?? [])
            .filter { $0.status == .complete }.map(\.id))
        XCTAssertEqual(survivors, filledIDs,
                       "Recorded reps kept their identity across shrink + regrow")
        let recreated = (block.performanceRecords ?? []).filter { $0.repNumber > 3 }
        XCTAssertTrue(recreated.allSatisfy { $0.status == .pending && $0.recordedTimeMs == nil },
                      "Regrown slots are fresh pending — no fabricated history")
    }

    // MARK: - Type change to a non-tracking block

    func testTypeChangeToNoteOnly_prunesEveryUnfilledSlot() throws {
        let (context, block, athlete) = try makeContextAndBlock(reps: 4)
        let timed = addSlot(context, block: block, athlete: athlete,
                            rep: 1, timeMs: 110_000, status: .complete)
        for rep in 2...4 {
            addSlot(context, block: block, athlete: athlete, rep: rep)
        }
        try context.save()

        // Weights has no per-rep tracking → capacity 0. (With rep 1 filled the
        // sheet's guard refuses this edit outright; the prune itself must
        // still protect filled data even at capacity 0.)
        let deleted = context.pruneUnfilledSlots(of: block, beyondRep: 0)
        try context.save()

        XCTAssertEqual(deleted, 3)
        XCTAssertEqual(repNumbers(of: block), [1])
        XCTAssertEqual(timed.recordedTimeMs, 110_000)
    }

    // MARK: - Multiple athletes

    func testPrune_appliesPerSlotAcrossAthletes() throws {
        let (context, block, athleteA) = try makeContextAndBlock(reps: 4)
        let athleteB = Athlete(firstName: "Second", lastName: "Athlete",
                               dateOfBirth: Date(timeIntervalSince1970: 0))
        context.insert(athleteB)
        for rep in 1...4 {
            addSlot(context, block: block, athlete: athleteA, rep: rep,
                    timeMs: rep == 4 ? 140_000 : nil,
                    status: rep == 4 ? .complete : .pending)
            addSlot(context, block: block, athlete: athleteB, rep: rep)
        }
        try context.save()

        let deleted = context.pruneUnfilledSlots(of: block, beyondRep: 3)
        try context.save()

        XCTAssertEqual(deleted, 1, "Only athlete B's pending rep 4 goes")
        XCTAssertEqual((block.performanceRecords ?? []).count, 7)
        XCTAssertEqual(block.highestFilledRepNumber, 4,
                       "Athlete A's recorded rep 4 survives")
    }

    // MARK: - Shared type rule

    func testCapturesPerRepData_truthTable() {
        let tracking: [BlockType] = [.paddleDistance, .paddleTimePieces,
                                     .paddlePyramid, .runDistance, .runIntervals]
        let nonTracking: [BlockType] = [.weights, .circuit, .core, .technique]

        for type in tracking {
            XCTAssertTrue(type.capturesPerRepData, "\(type) captures per-rep data")
        }
        for type in nonTracking {
            XCTAssertFalse(type.capturesPerRepData, "\(type) has no per-rep slots")
        }
        XCTAssertEqual(tracking.count + nonTracking.count, BlockType.allCases.count,
                       "Truth table covers every BlockType case")
    }
}
