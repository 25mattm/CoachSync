/// Full local wipe on club change or removal (multi-club tenancy slice 6). `SyncCoordinator`
/// calls this when the signed-in coach's club differs from the last club it synced under — a
/// club switch, or an explicit "no club" response after removal.
///
/// Deletes RAW, never through `SyncStore.save` — a wipe must never enqueue `PendingChange` DELETE
/// rows, or leaving/losing a club would push deletes against the club just left (or the club just
/// joined) on the next sync. Also clears the device-local coach identity so the coach re-confirms
/// "who am I" via the existing onboarding roster picker rather than risk a stale id
/// misattributing new records.

import Foundation
import SwiftData

/// Where `SyncCoordinator` remembers the club it last synced under, so it can detect a change on
/// the next sync trigger. Abstracted (mirrors `TokenStoring`) so tests can inject an in-memory
/// double instead of touching real `UserDefaults`.
protocol ClubMarkerStoring: AnyObject {
    var clubId: UUID? { get set }
}

/// `UserDefaults`-backed production implementation.
final class UserDefaultsClubMarker: ClubMarkerStoring {
    private let key = "CoachSync.lastKnownClubID"

    // `nonisolated` (the module defaults to MainActor): constructing the marker touches no isolated
    // state, so it stays callable from the nonisolated default argument in `SyncCoordinator.init`.
    nonisolated init() {}

    var clubId: UUID? {
        get { UserDefaults.standard.string(forKey: key).flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: key) }
    }
}

@MainActor
enum LocalWipe {

    /// Deletes every local model and clears the device-local coach identity. Either fully commits
    /// or fully rolls back — a thrown error leaves `context` exactly as it was before this call,
    /// mirroring the atomic-commit lesson `SyncPusher` already learned from a mid-batch 401.
    static func wipeAll(in context: ModelContext) throws {
        let sessions = (try? context.fetch(FetchDescriptor<CoachSession>())) ?? []
        sessions.forEach { context.deleteSessionCascade($0) }

        let teams = (try? context.fetch(FetchDescriptor<Team>())) ?? []
        teams.forEach { context.deleteTeamCascade($0) }

        let athletes = (try? context.fetch(FetchDescriptor<Athlete>())) ?? []
        athletes.forEach { context.deleteAthleteCascade($0) }

        let seasonArchives = (try? context.fetch(FetchDescriptor<SeasonArchive>())) ?? []
        seasonArchives.forEach { context.delete($0) }

        let coaches = (try? context.fetch(FetchDescriptor<Coach>())) ?? []
        coaches.forEach { context.delete($0) }

        // No existing wipe path clears the outbox itself — must be explicit, or a stale
        // PendingChange row from the club just left could get pushed against the new club.
        let pendingChanges = (try? context.fetch(FetchDescriptor<PendingChange>())) ?? []
        pendingChanges.forEach { context.delete($0) }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        CoachIdentity.clear()
    }

    /// Deletes every practice on this device — blocks, attendance, rep results, and session notes
    /// cascade with it — and drops their pending outbox rows. Same raw-delete contract as
    /// `wipeAll`: nothing is enqueued, so clearing a device can never push deletes to the club.
    static func wipeSessions(in context: ModelContext) throws {
        let sessions = (try? context.fetch(FetchDescriptor<CoachSession>())) ?? []
        sessions.forEach { context.deleteSessionCascade($0) }

        // A pending edit to a deleted practice would otherwise reach the pusher as "gone" and be
        // sent as a DELETE — exactly the club-wide delete this wipe exists to avoid.
        let sessionTypes: Set<String> = [
            CoachSession.syncEntityName, SessionBlock.syncEntityName, AttendanceRecord.syncEntityName,
            PerformanceRecord.syncEntityName, AthleteNote.syncEntityName,
        ]
        let pendingChanges = (try? context.fetch(FetchDescriptor<PendingChange>())) ?? []
        pendingChanges.filter { sessionTypes.contains($0.entityType) }.forEach { context.delete($0) }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
