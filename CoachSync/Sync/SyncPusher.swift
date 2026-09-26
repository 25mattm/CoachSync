/// Drains the `PendingChange` outbox to the backend (Stage 3b — the push half of LWW sync).
///
/// State-based + coalesced: the outbox rows are grouped per entity id, and the *current* local
/// state decides the action — a record that still exists is upserted (POST-with-id for a not-yet-
/// pushed insert, PUT for an update); a record that's gone is deleted. Upserts run parent→child and
/// deletes child→parent so referenced rows exist (and cascades are tolerated). Leaf records sync by
/// natural key (attendance by session+athlete, performance by block+athlete+rep), and the leaf /
/// membership *deletes* are covered by the parent's backend cascade, so they have no standalone call.
///
/// Outcomes per call: 2xx (or 404 on a delete = already cascaded) clears the rows; 409 drops them
/// (a conflict that won't resolve, e.g. a duplicate active membership); 401 stops and surfaces
/// re-auth; anything else (incl. transport failure) leaves the rows pending for the next run.

import Foundation
import SwiftData

@MainActor
struct SyncPusher {

    let client: BackendClient
    let token: String
    let context: ModelContext

    enum PushError: Error { case reauthRequired }

    /// What to do with an entity that has outbox rows. `notReady` is a record that still exists
    /// locally but can't be sent this run (a parent link is missing, or the body failed to encode) —
    /// it must stay pending, never fall through to the delete path as if it were gone.
    private enum UpsertPlan {
        case send(URLRequest)
        case gone
        case notReady
    }

    private struct PlannedOp {
        let type: String
        let id: UUID
        let rows: [PendingChange]
        let request: URLRequest
        let isDelete: Bool
        let isInsert: Bool
    }

    /// Drains the outbox. Returns the number of changes left pending because the backend
    /// definitively rejected them (a non-retriable 4xx — retrying the same payload would fail
    /// identically forever), so the caller can surface that to the coach instead of reporting a
    /// bare "success". Throws ``PushError/reauthRequired`` if the token was rejected (the caller
    /// should prompt a fresh sign-in).
    @discardableResult
    func push() async throws -> Int {
        let pending = (try? context.fetch(
            FetchDescriptor<PendingChange>(sortBy: [SortDescriptor(\.enqueuedAt)]))) ?? []
        guard !pending.isEmpty else { return 0 }

        // Coalesce per entity id, preserving first-seen order.
        var rows: [UUID: [PendingChange]] = [:]
        var order: [UUID] = []
        for change in pending {
            if rows[change.entityId] == nil { order.append(change.entityId) }
            rows[change.entityId, default: []].append(change)
        }

        var upserts: [PlannedOp] = []
        var deletes: [PlannedOp] = []
        var notReadyCount = 0
        for id in order {
            let changes = rows[id]!
            let type = changes[changes.count - 1].entityType
            let hasInsert = changes.contains { $0.operation == .insert }
            switch upsertPlan(type: type, id: id, isInsert: hasInsert) {
            case .send(let request):
                upserts.append(PlannedOp(type: type, id: id, rows: changes, request: request,
                                         isDelete: false, isInsert: hasInsert))
            case .notReady:
                notReadyCount += 1  // left pending (and reported) — retried on the next run
                print("SyncPusher: \(type) \(id) not ready to push — left pending")
            case .gone:
                if let request = deleteRequest(type: type, id: id) {
                    deletes.append(PlannedOp(type: type, id: id, rows: changes, request: request,
                                             isDelete: true, isInsert: false))
                } else {
                    clear(changes)  // gone + cascade-covered (leaf/membership delete) — nothing to send
                }
            }
        }
        // Parents before children; within a type, updates (PUT) before inserts (POST) so e.g. a
        // membership's leave (leftDate PUT) frees the active slot before a re-join POST — otherwise
        // the backend's "already an active member" guard 409s and the re-join is dropped.
        upserts.sort { (rank($0.type), $0.isInsert ? 1 : 0) < (rank($1.type), $1.isInsert ? 1 : 0) }
        deletes.sort { rank($0.type) > rank($1.type) }   // children first

        // `defer`, not a trailing call: `execute` throws `reauthRequired` on a 401, and ops that
        // already succeeded have had their outbox rows deleted from this (main) context but not yet
        // saved. Skipping the save on the throw path resurrects those rows, so the retry re-POSTs an
        // entity the backend already has — a 409, which `execute` clears, silently dropping the
        // coach's coalesced edits. Saving on every exit keeps the cleared rows cleared.
        var stuckCount = notReadyCount
        defer { try? context.save() }
        for op in upserts + deletes {
            if try await execute(op) {
                stuckCount += 1
            }
        }
        return stuckCount
    }

    // MARK: - Execute

    /// Returns `true` if this op is "stuck" — a definite client-side rejection (4xx, other than
    /// the already-handled 401/404-on-delete/409) that will fail identically on every retry until
    /// the underlying data changes.
    private func execute(_ op: PlannedOp) async throws -> Bool {
        let status: Int
        do {
            status = try await client.sendForStatus(op.request)
        } catch {
            return false  // transient (offline / TLS) — leave pending for the next run
        }
        switch status {
        case 200...299:
            clear(op.rows)
            return false
        case 404 where op.isDelete:
            clear(op.rows)  // already gone (the parent delete cascaded it) — treat as success
            return false
        case 401:
            throw PushError.reauthRequired
        case 409:
            clear(op.rows)
            print("SyncPusher: dropped \(op.type) \(op.id) on 409 conflict")
            return false
        case 400...499:
            // Backend validation rejected the payload as-is (e.g. a malformed guardian email) —
            // left pending (not dropped, so the data isn't silently lost) but reported as stuck
            // rather than transient, since resending the identical body will 4xx again forever.
            print("SyncPusher: \(op.type) \(op.id) stuck — status \(status)")
            return true
        default:
            print("SyncPusher: \(op.type) \(op.id) left pending — status \(status)")
            return false
        }
    }

    private func clear(_ rows: [PendingChange]) {
        for row in rows { context.delete(row) }
    }

    // MARK: - Upsert routing (model still present → POST-with-id on insert, else PUT)

    private func upsertPlan(type: String, id: UUID, isInsert: Bool) -> UpsertPlan {
        switch type {
        case "Coach":
            guard let c = fetch(Coach.self, id) else { return .gone }
            return upsert(isInsert, "/api/coaches", "/api/coaches/\(id)", SyncPush.coachRequest(c))
        case "Athlete":
            guard let a = fetch(Athlete.self, id) else { return .gone }
            return upsert(isInsert, "/api/athletes", "/api/athletes/\(id)", SyncPush.athleteRequest(a))
        case "Team":
            guard let t = fetch(Team.self, id) else { return .gone }
            return upsert(isInsert, "/api/teams", "/api/teams/\(id)", SyncPush.teamRequest(t))
        case "CoachSession":
            guard let s = fetch(CoachSession.self, id) else { return .gone }
            return upsert(isInsert, "/api/sessions", "/api/sessions/\(id)", SyncPush.sessionRequest(s))
        case "SessionBlock":
            guard let b = fetch(SessionBlock.self, id) else { return .gone }
            guard let sid = b.session?.id else { return .notReady }
            return upsert(isInsert, "/api/sessions/\(sid)/blocks", "/api/blocks/\(id)", SyncPush.blockRequest(b))
        case "AthleteNote":
            guard let n = fetch(AthleteNote.self, id) else { return .gone }
            guard let sid = n.session?.id else { return .notReady }
            return isInsert
                ? json("/api/sessions/\(sid)/notes", "POST", SyncPush.noteCreateRequest(n))
                : json("/api/notes/\(id)", "PUT", SyncPush.noteUpdateRequest(n))
        case "TeamMembership":
            guard let m = fetch(TeamMembership.self, id) else { return .gone }
            guard let tid = m.team?.id else { return .notReady }
            return isInsert
                ? json("/api/teams/\(tid)/members", "POST", SyncPush.membershipRequest(m))
                : json("/api/teams/\(tid)/members/\(id)", "PUT", SyncPush.membershipRequest(m))
        case "AttendanceRecord":
            guard let r = fetch(AttendanceRecord.self, id) else { return .gone }
            guard let sid = r.session?.id else { return .notReady }
            return json("/api/sessions/\(sid)/attendance", "PUT", SyncPush.attendanceRequest(r))
        case "PerformanceRecord":
            guard let p = fetch(PerformanceRecord.self, id) else { return .gone }
            guard let bid = p.sessionBlock?.id else { return .notReady }
            return json("/api/blocks/\(bid)/performance", "PUT", SyncPush.performanceRequest(p))
        case "TechnicalAssessment":
            guard let a = fetch(TechnicalAssessment.self, id) else { return .gone }
            guard let aid = a.athlete?.id else { return .notReady }
            return upsert(isInsert, "/api/athletes/\(aid)/assessments", "/api/assessments/\(id)", SyncPush.assessmentRequest(a))
        case "FitnessTestResult":
            guard let f = fetch(FitnessTestResult.self, id) else { return .gone }
            guard let aid = f.athlete?.id else { return .notReady }
            return upsert(isInsert, "/api/athletes/\(aid)/fitness-tests", "/api/fitness-tests/\(id)", SyncPush.fitnessTestRequest(f))
        case "RegattaResult":
            guard let r = fetch(RegattaResult.self, id) else { return .gone }
            guard let aid = r.athlete?.id else { return .notReady }
            return upsert(isInsert, "/api/athletes/\(aid)/regatta-results", "/api/regatta-results/\(id)", SyncPush.regattaRequest(r))
        case "DevelopmentNote":
            guard let n = fetch(DevelopmentNote.self, id) else { return .gone }
            guard let aid = n.athlete?.id else { return .notReady }
            return upsert(isInsert, "/api/athletes/\(aid)/journal", "/api/journal/\(id)", SyncPush.journalRequest(n))
        case "KTCAssessment":
            guard let k = fetch(KTCAssessment.self, id) else { return .gone }
            guard let aid = k.athlete?.id else { return .notReady }
            return upsert(isInsert, "/api/athletes/\(aid)/ktc", "/api/ktc/\(id)", SyncPush.ktcRequest(k))
        case "HeightRecord":
            guard let h = fetch(HeightRecord.self, id) else { return .gone }
            guard let aid = h.athlete?.id else { return .notReady }
            return upsert(isInsert, "/api/athletes/\(aid)/heights", "/api/heights/\(id)", SyncPush.heightRequest(h))
        default:
            return .gone
        }
    }

    /// Per-id delete endpoint. Leaf records (attendance, performance) and hard-deleted memberships
    /// have no standalone delete — their removal rides the parent's backend cascade — so return nil.
    private func deleteRequest(type: String, id: UUID) -> URLRequest? {
        let path: String
        switch type {
        case "Coach":               path = "/api/coaches/\(id)"
        case "Athlete":             path = "/api/athletes/\(id)"
        case "Team":                path = "/api/teams/\(id)"
        case "CoachSession":        path = "/api/sessions/\(id)"
        case "SessionBlock":        path = "/api/blocks/\(id)"
        case "AthleteNote":         path = "/api/notes/\(id)"
        case "TechnicalAssessment": path = "/api/assessments/\(id)"
        case "FitnessTestResult":   path = "/api/fitness-tests/\(id)"
        case "RegattaResult":       path = "/api/regatta-results/\(id)"
        case "DevelopmentNote":     path = "/api/journal/\(id)"
        case "KTCAssessment":       path = "/api/ktc/\(id)"
        case "HeightRecord":        path = "/api/heights/\(id)"
        default:                    return nil
        }
        return client.authorizedRequest(path: path, method: "DELETE", token: token)
    }

    private func upsert<Body: Encodable>(
        _ isInsert: Bool, _ createPath: String, _ updatePath: String, _ body: Body) -> UpsertPlan {
        isInsert ? json(createPath, "POST", body) : json(updatePath, "PUT", body)
    }

    /// A body that fails to encode is `notReady`, not `gone` — the record still exists.
    private func json<Body: Encodable>(_ path: String, _ method: String, _ body: Body) -> UpsertPlan {
        guard let request = try? client.jsonRequest(path: path, method: method, token: token, body: body) else {
            return .notReady
        }
        return .send(request)
    }

    // Concrete per-type fetches (SwiftData `#Predicate` needs the concrete keypath, not a generic
    // one — mirrors the forward `SyncMapping.existing*` lookups).
    private func fetch(_: Coach.Type, _ id: UUID) -> Coach? {
        var d = FetchDescriptor<Coach>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? context.fetch(d).first
    }
    private func fetch(_: Athlete.Type, _ id: UUID) -> Athlete? {
        var d = FetchDescriptor<Athlete>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? context.fetch(d).first
    }
    private func fetch(_: Team.Type, _ id: UUID) -> Team? {
        var d = FetchDescriptor<Team>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? context.fetch(d).first
    }
    private func fetch(_: CoachSession.Type, _ id: UUID) -> CoachSession? {
        var d = FetchDescriptor<CoachSession>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? context.fetch(d).first
    }
    private func fetch(_: SessionBlock.Type, _ id: UUID) -> SessionBlock? {
        var d = FetchDescriptor<SessionBlock>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? context.fetch(d).first
    }
    private func fetch(_: AthleteNote.Type, _ id: UUID) -> AthleteNote? {
        var d = FetchDescriptor<AthleteNote>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? context.fetch(d).first
    }
    private func fetch(_: TeamMembership.Type, _ id: UUID) -> TeamMembership? {
        var d = FetchDescriptor<TeamMembership>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? context.fetch(d).first
    }
    private func fetch(_: AttendanceRecord.Type, _ id: UUID) -> AttendanceRecord? {
        var d = FetchDescriptor<AttendanceRecord>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? context.fetch(d).first
    }
    private func fetch(_: PerformanceRecord.Type, _ id: UUID) -> PerformanceRecord? {
        var d = FetchDescriptor<PerformanceRecord>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? context.fetch(d).first
    }
    private func fetch(_: TechnicalAssessment.Type, _ id: UUID) -> TechnicalAssessment? {
        var d = FetchDescriptor<TechnicalAssessment>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? context.fetch(d).first
    }
    private func fetch(_: FitnessTestResult.Type, _ id: UUID) -> FitnessTestResult? {
        var d = FetchDescriptor<FitnessTestResult>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? context.fetch(d).first
    }
    private func fetch(_: RegattaResult.Type, _ id: UUID) -> RegattaResult? {
        var d = FetchDescriptor<RegattaResult>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? context.fetch(d).first
    }
    private func fetch(_: DevelopmentNote.Type, _ id: UUID) -> DevelopmentNote? {
        var d = FetchDescriptor<DevelopmentNote>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? context.fetch(d).first
    }
    private func fetch(_: KTCAssessment.Type, _ id: UUID) -> KTCAssessment? {
        var d = FetchDescriptor<KTCAssessment>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? context.fetch(d).first
    }
    private func fetch(_: HeightRecord.Type, _ id: UUID) -> HeightRecord? {
        var d = FetchDescriptor<HeightRecord>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// Parent→child ordering rank for upserts (deletes use the reverse).
    private func rank(_ type: String) -> Int {
        switch type {
        case "Coach":  return 0
        case "Athlete": return 1
        case "Team":   return 2
        case "CoachSession": return 3
        case "TechnicalAssessment", "FitnessTestResult", "RegattaResult",
             "DevelopmentNote", "KTCAssessment", "HeightRecord": return 3
        case "TeamMembership", "SessionBlock": return 4
        case "AthleteNote", "AttendanceRecord": return 5
        case "PerformanceRecord": return 6
        default: return 9
        }
    }
}
