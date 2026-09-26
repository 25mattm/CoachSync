/// Stage 3c read path: pulls the shared club from the backend into the LIVE SwiftData store,
/// merging last-write-wins (an un-pushed local change always wins), then snapshot-diff deletes the
/// local records the server no longer has. Pair with `SyncPusher` (push-then-pull) in `SyncCoordinator`.

import Foundation
import SwiftData

@MainActor
struct SyncService {

    let client: BackendClient

    init(client: BackendClient = BackendClient()) {
        self.client = client
    }

    /// Pulls every resource into `ctx` and reconciles deletions. Throws ``BackendError`` on a failed
    /// request (the diff only runs once every GET has succeeded, so a mid-pull failure never deletes).
    func pull(into liveContext: ModelContext, token: String) async throws {
        // Pull into a PRIVATE context on the same container — never the live/main context. Between the
        // ~20 awaited GETs below the user may save an edit on the main context; if the in-flight pulled
        // rows lived there, that SyncStore.save would sweep them up — stamping updatedAt=.now and
        // enqueuing a PendingChange per pulled row (corrupting LWW and re-pushing the whole snapshot). A
        // separate context keeps them invisible to that save until we commit them here with a raw save
        // (no enqueue); the live store observes the committed result via @Query, as it did the CloudKit import.
        let ctx = ModelContext(liveContext.container)
        var pending = pendingIDs(in: ctx)   // for the LWW upserts; re-read before the diff (see step 5)

        // 1 — top-level resources (paged).
        let coaches: [CoachDTO] = try await client.getPaged("/api/coaches", token: token)
        let athletes: [AthleteDTO] = try await client.getPaged("/api/athletes", token: token)
        let teams: [TeamDTO] = try await client.getPaged("/api/teams", token: token)
        let sessions: [SessionDTO] = try await client.getPaged("/api/sessions", token: token)
        coaches.forEach { SyncMapping.upsertCoach($0, in: ctx, pending: pending) }
        athletes.forEach { SyncMapping.upsertAthlete($0, in: ctx, pending: pending) }
        teams.forEach { SyncMapping.upsertTeam($0, in: ctx, pending: pending) }
        sessions.forEach { SyncMapping.upsertSession($0, in: ctx, pending: pending) }

        // 2 — per-team memberships.
        var membershipIDs: Set<UUID> = []
        for team in teams {
            let members: [TeamMembershipDTO] = try await client.getList(
                "/api/teams/\(team.id.uuidString)/members", token: token)
            members.forEach {
                SyncMapping.upsertMembership($0, in: ctx, pending: pending); membershipIDs.insert($0.id)
            }
        }

        // 3 — per-session blocks / attendance / notes; per-block performance (leaf = natural-key).
        var blockIDs: Set<UUID> = []
        var noteIDs: Set<UUID> = []
        for dto in sessions {
            guard let session = liveSession(dto.id, in: ctx) else { continue }
            let blocks: [BlockDTO] = try await client.getList(
                "/api/sessions/\(dto.id.uuidString)/blocks", token: token)
            blocks.forEach { SyncMapping.upsertBlock($0, in: ctx, pending: pending); blockIDs.insert($0.id) }
            let attendance: [AttendanceDTO] = try await client.getList(
                "/api/sessions/\(dto.id.uuidString)/attendance", token: token)
            attendance.forEach { SyncMapping.upsertAttendance($0, session: session, in: ctx, pending: pending) }
            let notes: [NoteDTO] = try await client.getList(
                "/api/sessions/\(dto.id.uuidString)/notes", token: token)
            notes.forEach { SyncMapping.upsertNote($0, in: ctx, pending: pending); noteIDs.insert($0.id) }
            for blockDTO in blocks {
                guard let block = liveBlock(blockDTO.id, in: ctx) else { continue }
                let perf: [PerformanceDTO] = try await client.getList(
                    "/api/blocks/\(blockDTO.id.uuidString)/performance", token: token)
                perf.forEach { SyncMapping.upsertPerformance($0, block: block, in: ctx, pending: pending) }
            }
        }

        // 4 — per-athlete domains.
        var assessmentIDs: Set<UUID> = [], fitnessIDs: Set<UUID> = [], regattaIDs: Set<UUID> = []
        var journalIDs: Set<UUID> = [], ktcIDs: Set<UUID> = [], heightIDs: Set<UUID> = []
        for athlete in athletes {
            let aid = athlete.id.uuidString
            let assessments: [AssessmentDTO] = try await client.getList("/api/athletes/\(aid)/assessments", token: token)
            assessments.forEach { SyncMapping.upsertAssessment($0, in: ctx, pending: pending); assessmentIDs.insert($0.id) }
            let fitness: [FitnessTestDTO] = try await client.getList("/api/athletes/\(aid)/fitness-tests", token: token)
            fitness.forEach { SyncMapping.upsertFitnessTest($0, in: ctx, pending: pending); fitnessIDs.insert($0.id) }
            let regatta: [RegattaResultDTO] = try await client.getList("/api/athletes/\(aid)/regatta-results", token: token)
            regatta.forEach { SyncMapping.upsertRegatta($0, in: ctx, pending: pending); regattaIDs.insert($0.id) }
            let journal: [JournalDTO] = try await client.getList("/api/athletes/\(aid)/journal", token: token)
            journal.forEach { SyncMapping.upsertJournal($0, in: ctx, pending: pending); journalIDs.insert($0.id) }
            let ktc: [KtcDTO] = try await client.getList("/api/athletes/\(aid)/ktc", token: token)
            ktc.forEach { SyncMapping.upsertKtc($0, in: ctx, pending: pending); ktcIDs.insert($0.id) }
            let heights: [HeightRecordDTO] = try await client.getList("/api/athletes/\(aid)/heights", token: token)
            heights.forEach { SyncMapping.upsertHeight($0, in: ctx, pending: pending); heightIDs.insert($0.id) }
        }

        // 5 — snapshot-diff deletion. A local record absent from the (now complete) server snapshot
        // is deleted, UNLESS it has a pending outbox entry (an un-pushed offline create/edit). Parent
        // types cascade first, so their children are gone before the child diffs run. Attendance and
        // performance aren't diffed here — their removal rides the parent session/block cascade.
        //
        // Safety valve: a snapshot with NO top-level records is almost always a backend/auth glitch
        // (wrong/empty club, transient failure), not a real wipe — running the diff then would mass-
        // delete the device's whole roster. A genuinely empty club has nothing local to diff anyway,
        // so skipping is safe; a real "everything deleted" reconciles on the next non-empty pull.
        // Re-read the outbox HERE (not only at the start): an edit the user committed mid-pull enqueues
        // a PendingChange, and the diff must see it so a record created during this pull isn't deleted
        // as "absent from the server snapshot".
        pending = pendingIDs(in: ctx)
        let serverEmpty = coaches.isEmpty && athletes.isEmpty && teams.isEmpty && sessions.isEmpty
        if serverEmpty {
            print("SyncService: empty server snapshot — skipping snapshot-diff to protect local data")
        } else {
            diffDelete(Coach.self, server: Set(coaches.map(\.id)), pending: pending, in: ctx) { ctx.delete($0) }
            diffDelete(Athlete.self, server: Set(athletes.map(\.id)), pending: pending, in: ctx) { ctx.deleteAthleteCascade($0) }
            diffDelete(Team.self, server: Set(teams.map(\.id)), pending: pending, in: ctx) { ctx.deleteTeamCascade($0) }
            diffDelete(CoachSession.self, server: Set(sessions.map(\.id)), pending: pending, in: ctx) { ctx.deleteSessionCascade($0) }
            diffDelete(SessionBlock.self, server: blockIDs, pending: pending, in: ctx) { ctx.deleteBlockCascade($0) }
            diffDelete(TechnicalAssessment.self, server: assessmentIDs, pending: pending, in: ctx) { ctx.deleteAssessmentCascade($0) }
            diffDelete(AthleteNote.self, server: noteIDs, pending: pending, in: ctx) { ctx.delete($0) }
            diffDelete(TeamMembership.self, server: membershipIDs, pending: pending, in: ctx) { ctx.delete($0) }
            diffDelete(FitnessTestResult.self, server: fitnessIDs, pending: pending, in: ctx) { ctx.delete($0) }
            diffDelete(RegattaResult.self, server: regattaIDs, pending: pending, in: ctx) { ctx.delete($0) }
            diffDelete(DevelopmentNote.self, server: journalIDs, pending: pending, in: ctx) { ctx.delete($0) }
            diffDelete(KTCAssessment.self, server: ktcIDs, pending: pending, in: ctx) { ctx.delete($0) }
            diffDelete(HeightRecord.self, server: heightIDs, pending: pending, in: ctx) { ctx.delete($0) }
        }

        // Raw save — pulled rows must NOT re-enqueue (this isn't a user edit; `PendingChange` is
        // local-only). Committing immediately also bounds any window where a concurrent user save
        // could observe these in-flight changes.
        try ctx.save()
    }

    private func pendingIDs(in ctx: ModelContext) -> Set<UUID> {
        let changes = (try? ctx.fetch(FetchDescriptor<PendingChange>())) ?? []
        return Set(changes.map(\.entityId))
    }

    // Indexed single-row lookups (mirroring SyncPusher's per-type fetches): a `#Predicate` filter
    // pushes the match into the fetch instead of loading every row and scanning, so the per-session
    // and per-block lookups in `pull` don't turn the snapshot into an O(n²) walk.
    private func liveSession(_ id: UUID, in ctx: ModelContext) -> CoachSession? {
        var d = FetchDescriptor<CoachSession>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? ctx.fetch(d).first
    }

    private func liveBlock(_ id: UUID, in ctx: ModelContext) -> SessionBlock? {
        var d = FetchDescriptor<SessionBlock>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? ctx.fetch(d).first
    }

    private func diffDelete<T: PersistentModel & SyncedModel>(
        _: T.Type, server: Set<UUID>, pending: Set<UUID>, in ctx: ModelContext, delete: (T) -> Void) {
        let all = (try? ctx.fetch(FetchDescriptor<T>())) ?? []
        for model in all where !server.contains(model.id) && !pending.contains(model.id) {
            delete(model)
        }
    }
}
