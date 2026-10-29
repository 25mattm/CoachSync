/// Hand-rolled cascading-delete helpers for `ModelContext`.
///
/// CloudKit doesn't support `.cascade` delete rules — every `@Relationship` in
/// the schema must use `.nullify` or `.noAction`. This file replaces the
/// cascade behavior with explicit walks that delete a model's children before
/// deleting the model itself, so destructive UI flows don't leave orphan rows.
///
/// Use these instead of `modelContext.delete(_:)` whenever you're removing a
/// model that owns children. Leaf models (KTCAssessment, DevelopmentNote,
/// RegattaResult, AthleteNote, etc.) don't need a helper — plain delete is
/// fine because they have no child relationships.

import Foundation
import SwiftData

extension ModelContext {

    /// Deletes an athlete and every record that hangs off them.
    /// Mirrors what `.cascade` did pre-CloudKit-prep. Uses optional chaining
    /// because CloudKit-compatible to-many relationships are `[T]?` and may
    /// be `nil` before any children have ever been attached.
    func deleteAthleteCascade(_ athlete: Athlete) {
        athlete.memberships?.forEach { delete($0) }
        athlete.attendanceRecords?.forEach { delete($0) }
        athlete.performanceRecords?.forEach { delete($0) }
        athlete.notes?.forEach { delete($0) }
        athlete.fitnessTestResults?.forEach { delete($0) }
        athlete.regattaResults?.forEach { delete($0) }
        athlete.technicalAssessments?.forEach { deleteAssessmentCascade($0) }
        athlete.heightRecords?.forEach { delete($0) }
        athlete.developmentNotes?.forEach { delete($0) }
        athlete.ktcAssessments?.forEach { delete($0) }
        delete(athlete)
    }

    /// Deletes a team and its membership join records.
    /// Sessions are intentionally retained (the original cascade behavior was
    /// nullify-only for sessions, so they survive with `team = nil`).
    func deleteTeamCascade(_ team: Team) {
        team.memberships?.forEach { delete($0) }
        delete(team)
    }

    /// Deletes a session and every child record (blocks with their per-rep
    /// performance records, attendance records, athlete notes).
    func deleteSessionCascade(_ session: CoachSession) {
        session.sessionBlocks?.forEach { deleteBlockCascade($0) }
        session.attendanceRecords?.forEach { delete($0) }
        session.athleteNotes?.forEach { delete($0) }
        delete(session)
    }

    /// Deletes a session block and its per-rep performance records. Block-anchored
    /// coaching notes are deliberately NOT deleted — they're recorded history owned by
    /// the athlete/session, so the `.nullify` rule on `AthleteNote.sessionBlock` detaches
    /// and preserves them (mirrors the backend's `BlockService.delete`). Deleting the
    /// owning session still removes its notes — see `deleteSessionCascade`.
    func deleteBlockCascade(_ block: SessionBlock) {
        block.performanceRecords?.forEach { delete($0) }
        delete(block)
    }

    /// Deletes a technical assessment and its per-factor ratings.
    func deleteAssessmentCascade(_ assessment: TechnicalAssessment) {
        assessment.ratings?.forEach { delete($0) }
        delete(assessment)
    }

    /// Deletes a block's unfilled `PerformanceRecord` slots whose rep number
    /// exceeds `capacity` — the orphans left behind when an edit shrinks the
    /// block's rep count (capacity 0 covers a change to a block type with no
    /// per-rep tracking). Slots holding coach-recorded data (a time, DNS, or
    /// DNF) are never deleted here; `AddBlockSheet` refuses any edit that
    /// would leave one beyond capacity. Returns the number of slots deleted.
    /// Does not save — callers own the save, matching the other helpers.
    @discardableResult
    func pruneUnfilledSlots(of block: SessionBlock, beyondRep capacity: Int) -> Int {
        let orphans = (block.performanceRecords ?? []).filter {
            $0.repNumber > capacity && !$0.holdsRecordedData
        }
        orphans.forEach { delete($0) }
        return orphans.count
    }

    /// Reconciles one block's `PerformanceRecord` slots against the present
    /// athletes: prunes unfilled slots beyond the block's rep capacity, prunes
    /// unfilled slots of athletes no longer present (so a present-then-absent
    /// athlete doesn't keep phantom practice history), and inserts a missing
    /// slot per present athlete × rep. Slots holding recorded data are always
    /// kept. Mirrors the backend's `SlotGenerationService.planBlock`; both
    /// run `shared/fixtures/slot-reconciliation.json`. Idempotent. Returns the
    /// number of slots changed. Does not save.
    @discardableResult
    func reconcileSlots(of block: SessionBlock, presentAthletes: [Athlete]) -> Int {
        let capturesData = block.blockType.capturesPerRepData
        let totalReps = capturesData ? max(block.repetitionCount, 1) : 0

        // Heal stranded unfilled slots beyond the current rep capacity
        // (capacity 0 for types with no per-rep tracking).
        var changes = pruneUnfilledSlots(of: block, beyondRep: totalReps)
        guard capturesData else { return changes }

        let presentIDs = Set(presentAthletes.map { $0.id })
        for record in block.performanceRecords ?? [] {
            guard record.repNumber <= totalReps, // beyond capacity: already pruned above
                  let athleteID = record.athlete?.id,
                  !presentIDs.contains(athleteID),
                  !record.holdsRecordedData else { continue }
            delete(record)
            changes += 1
        }

        for athlete in presentAthletes {
            for rep in 1...totalReps {
                let exists = (block.performanceRecords ?? []).contains {
                    $0.athlete?.id == athlete.id && $0.repNumber == rep
                }
                if !exists {
                    insert(PerformanceRecord(athlete: athlete, sessionBlock: block, repNumber: rep))
                    changes += 1
                }
            }
        }
        return changes
    }
}
