import XCTest
import SwiftData
@testable import CoachSync

/// Multi-club tenancy slice 6: local wipe when the signed-in coach's club differs from the one
/// this device last synced under (a club switch, or an explicit "no club" response after
/// removal). Reuses `StubURLProtocol` (AuthTests.swift) and the `CoachSyncContainer.schema`-based
/// in-memory context pattern established in SyncTests.swift — `TestSupport.schema` is missing
/// `Coach`/`PendingChange`, both needed here.

private let clubA = UUID(uuidString: "A0000000-0000-0000-0000-00000000000A")!
private let clubB = UUID(uuidString: "B0000000-0000-0000-0000-00000000000B")!

private let clubACoachID = UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!
private let clubAAthleteID = UUID(uuidString: "A1000000-0000-0000-0000-000000000002")!
private let clubATeamID = UUID(uuidString: "A1000000-0000-0000-0000-000000000003")!
private let clubASessionID = UUID(uuidString: "A1000000-0000-0000-0000-000000000004")!
private let clubABlockID = UUID(uuidString: "A1000000-0000-0000-0000-000000000005")!

private let clubBAthleteID = UUID(uuidString: "B1000000-0000-0000-0000-000000000002")!
private let clubBTeamID = UUID(uuidString: "B1000000-0000-0000-0000-000000000003")!

@MainActor
private func makeContext() throws -> ModelContext {
    let config = ModelConfiguration(schema: CoachSyncContainer.schema, isStoredInMemoryOnly: true)
    return ModelContext(try ModelContainer(for: CoachSyncContainer.schema, configurations: config))
}

/// In-memory `ClubMarkerStoring` test double — never touches real `UserDefaults`, so no test
/// depends on (or leaks) state across runs. Also used by `SyncCoordinatorTests` in SyncTests.swift
/// to isolate its pre-existing 401 test from the production `UserDefaultsClubMarker` default.
final class InMemoryClubMarker: ClubMarkerStoring {
    var clubId: UUID?
    init(_ clubId: UUID? = nil) { self.clubId = clubId }
}

private final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var paths: [String] = []
    func record(_ path: String) { lock.lock(); paths.append(path); lock.unlock() }
}

// MARK: - LocalWipe.wipeAll direct coverage

@MainActor
final class LocalWipeTests: XCTestCase {

    override func tearDown() {
        CoachIdentity.clear()
        super.tearDown()
    }

    /// Seeds one row of every schema type — via a realistic object graph, not orphan rows — plus
    /// the outbox and the device-local coach identity, then asserts a full wipe. Isolates "did the
    /// wipe delete everything" from any `SyncCoordinator` timing concern.
    func testLocalWipeClearsEveryTable() throws {
        let ctx = try makeContext()

        let coach = Coach(name: "Pat")
        ctx.insert(coach)
        CoachIdentity.setCurrent(coach)

        let athlete = Athlete(firstName: "Ada", lastName: "L", dateOfBirth: Date(timeIntervalSince1970: 0))
        let team = Team(teamName: "U14")
        let session = CoachSession(sessionName: "Tue", scheduledDate: .now, team: team)
        let block = SessionBlock(blockName: "Paddle", blockType: .paddleDistance, sortOrder: 0, session: session)
        ctx.insert(athlete); ctx.insert(team); ctx.insert(session); ctx.insert(block)

        ctx.insert(TeamMembership(athlete: athlete, team: team))
        ctx.insert(AttendanceRecord(athlete: athlete, session: session))
        ctx.insert(PerformanceRecord(athlete: athlete, sessionBlock: block, repNumber: 1))
        ctx.insert(AthleteNote(noteText: "note", athlete: athlete, session: session, sessionBlock: block))
        ctx.insert(FitnessTestResult(testType: "2k", result: 480, athlete: athlete))
        ctx.insert(RegattaResult(regattaName: "Regatta", regattaDate: .now,
                                 eventDistance: 1000, resultTimeMs: 240_000, athlete: athlete))
        let assessment = TechnicalAssessment(athlete: athlete)
        ctx.insert(assessment)
        ctx.insert(TechnicalRating(category: "Catch", factor: "Timing", score: 3, assessment: assessment))
        ctx.insert(HeightRecord(heightCm: 170, athlete: athlete))
        ctx.insert(DevelopmentNote(text: "journal", athlete: athlete))
        ctx.insert(KTCAssessment(window: "General Prep 1", setupRecoveryScore: 3,
                                 catchScore: 3, propulsionDrawScore: 3, exitScore: 3, athlete: athlete))
        ctx.insert(SeasonArchive(seasonYear: 2026, totalAthletes: 1, totalSessions: 1, totalKm: 5))
        ctx.insert(PendingChange(entityType: "Athlete", entityId: athlete.id, operation: .update))
        try ctx.save()

        try LocalWipe.wipeAll(in: ctx)

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Athlete>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Team>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<TeamMembership>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<CoachSession>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<SessionBlock>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<AttendanceRecord>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<PerformanceRecord>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<AthleteNote>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<FitnessTestResult>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<RegattaResult>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<TechnicalAssessment>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<TechnicalRating>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<HeightRecord>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<DevelopmentNote>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<KTCAssessment>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<SeasonArchive>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Coach>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<PendingChange>()).count, 0, "outbox must be flushed, not pushed")
        XCTAssertNil(CoachIdentity.currentID, "device-local coach identity must be cleared")
    }

    /// Settings → Reset Session Data. Must clear practices from this device only: no DELETE may be
    /// queued for the club (it would wipe every coach's data), and a pending edit to a cleared
    /// practice must be dropped too — the pusher would otherwise see it as "gone" and send a DELETE.
    func testWipeSessionsIsDeviceLocalAndKeepsAthleteData() throws {
        let ctx = try makeContext()
        let athlete = Athlete(firstName: "Ada", lastName: "L", dateOfBirth: Date(timeIntervalSince1970: 0))
        let session = CoachSession(sessionName: "Tue", scheduledDate: .now)
        let block = SessionBlock(blockName: "Paddle", blockType: .paddleDistance, sortOrder: 0, session: session)
        ctx.insert(athlete); ctx.insert(session); ctx.insert(block)
        ctx.insert(AttendanceRecord(athlete: athlete, session: session))
        ctx.insert(AthleteNote(noteText: "note", athlete: athlete, session: session, sessionBlock: block))
        ctx.insert(HeightRecord(heightCm: 170, athlete: athlete))
        ctx.insert(PendingChange(entityType: "CoachSession", entityId: session.id, operation: .update))
        ctx.insert(PendingChange(entityType: "SessionBlock", entityId: block.id, operation: .update))
        ctx.insert(PendingChange(entityType: "Athlete", entityId: athlete.id, operation: .update))
        try ctx.save()

        try LocalWipe.wipeSessions(in: ctx)

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<CoachSession>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<SessionBlock>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<AttendanceRecord>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<AthleteNote>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Athlete>()).count, 1, "athletes are kept")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<HeightRecord>()).count, 1, "athlete history is kept")
        let outbox = try ctx.fetch(FetchDescriptor<PendingChange>())
        XCTAssertEqual(outbox.map(\.entityType), ["Athlete"],
                       "session edits are dropped, nothing new is queued, unrelated pending edits survive")
        XCTAssertFalse(outbox.contains { $0.operation == .delete }, "a device reset must never queue a DELETE")
    }
}

// MARK: - SyncCoordinator-level acceptance tests (multi-club tenancy plan §4 item 6)

@MainActor
final class ClubChangeWipeTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.handler = nil
        CoachIdentity.clear()
        super.tearDown()
    }

    private func client() -> BackendClient {
        BackendClient(baseURL: URL(string: "http://test.local")!, session: StubURLProtocol.session())
    }

    private func page(_ item: String) -> String {
        "{\"content\":[\(item)],\"page\":{\"size\":500,\"number\":0,\"totalElements\":1,\"totalPages\":1}}"
    }
    private func emptyPage() -> String {
        "{\"content\":[],\"page\":{\"size\":500,\"number\":0,\"totalElements\":0,\"totalPages\":1}}"
    }

    /// Seeds club A's data directly (raw insert, bypassing `SyncStore`) — mirrors how a real
    /// device's store looks after prior syncs, not how a fresh local edit would enqueue.
    @discardableResult
    private func seedClubAData(in ctx: ModelContext) -> (athlete: Athlete, team: Team, session: CoachSession) {
        let coach = Coach(name: "ClubACoach")
        coach.id = clubACoachID
        let athlete = Athlete(firstName: "ClubA", lastName: "Athlete", dateOfBirth: Date(timeIntervalSince1970: 0))
        athlete.id = clubAAthleteID
        let team = Team(teamName: "ClubA Team")
        team.id = clubATeamID
        let session = CoachSession(sessionName: "ClubA Session", scheduledDate: .now, team: team)
        session.id = clubASessionID
        let block = SessionBlock(blockName: "Paddle", blockType: .paddleDistance, sortOrder: 0, session: session)
        block.id = clubABlockID
        // SeasonArchive is deliberately app-only and never diffed by SyncService.pull (see its own
        // doc comment) — including one here means testClubSwitchWipe below can't accidentally pass
        // because ORDINARY snapshot-diff happened to clean up everything on its own; only the wipe
        // touches this table.
        let archive = SeasonArchive(seasonYear: 2026, totalAthletes: 1, totalSessions: 1, totalKm: 5)
        ctx.insert(coach); ctx.insert(athlete); ctx.insert(team); ctx.insert(session); ctx.insert(block)
        ctx.insert(archive)
        try? ctx.save()
        return (athlete, team, session)
    }

    /// `RemovedCoachPurgeTest` — the plan's named acceptance test. A fresh sign-in that returns no
    /// club (removed/pending) must purge every trace of the old club's data.
    func testRemovedCoachPurge() async throws {
        let ctx = try makeContext()
        seedClubAData(in: ctx)

        // Every top-level list is empty, so the pull's per-team/session/athlete sub-resource
        // loops never fire — a blanket empty paged envelope is safe for every request.
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(self.emptyPage().utf8))
        }

        let marker = InMemoryClubMarker(clubA)
        let coordinator = SyncCoordinator(context: ctx, client: client(), tokenProvider: { "tok" },
                                          clubIdProvider: { nil }, clubMarker: marker)
        await coordinator.syncNow()

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Athlete>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Team>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<CoachSession>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<SessionBlock>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Coach>()).count, 0)
        XCTAssertNil(marker.clubId)
    }

    /// `ClubSwitchWipeTest` — the plan's other named acceptance test. A fresh sign-in into a
    /// DIFFERENT club must purge club A's data and let club B's fresh pull repopulate cleanly.
    func testClubSwitchWipe() async throws {
        let ctx = try makeContext()
        seedClubAData(in: ctx)

        let ts = "2026-06-01T10:00:00Z"
        let clubBAthlete = "{\"id\":\"\(clubBAthleteID)\",\"firstName\":\"ClubB\",\"lastName\":\"Athlete\",\"dateOfBirth\":\"2010-06-15\",\"gender\":null,\"guardianName\":null,\"guardianPhone\":null,\"guardianEmail\":null,\"active\":true,\"developmentStage\":\"INITIATION\",\"createdAt\":\"\(ts)\",\"updatedAt\":\"\(ts)\"}"
        let clubBTeam = "{\"id\":\"\(clubBTeamID)\",\"teamName\":\"ClubB Team\",\"teamDescription\":null,\"archived\":false,\"createdAt\":\"\(ts)\",\"updatedAt\":\"\(ts)\"}"
        // Paged envelope only for the four top-level list endpoints; bare `[]` for every
        // sub-resource GET the now-non-empty athlete/team lists will trigger — matches
        // SyncServiceTests.testPullMergesClubIntoLiveStore's stubbing convention exactly.
        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let json: String
            if path == "/api/athletes" { json = self.page(clubBAthlete) }
            else if path == "/api/teams" { json = self.page(clubBTeam) }
            else if path == "/api/coaches" || path == "/api/sessions" { json = self.emptyPage() }
            else { json = "[]" }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let marker = InMemoryClubMarker(clubA)
        let coordinator = SyncCoordinator(context: ctx, client: client(), tokenProvider: { "tok" },
                                          clubIdProvider: { clubB }, clubMarker: marker)
        await coordinator.syncNow()

        let athleteIDs = Set(try ctx.fetch(FetchDescriptor<Athlete>()).map(\.id))
        XCTAssertFalse(athleteIDs.contains(clubAAthleteID), "club A's athlete must be gone")
        XCTAssertTrue(athleteIDs.contains(clubBAthleteID), "club B's athlete must be pulled in")
        let teamIDs = Set(try ctx.fetch(FetchDescriptor<Team>()).map(\.id))
        XCTAssertFalse(teamIDs.contains(clubATeamID), "club A's team must be gone")
        XCTAssertTrue(teamIDs.contains(clubBTeamID), "club B's team must be pulled in")
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<PendingChange>()).isEmpty)
        // SeasonArchive is never diffed by SyncService.pull (see seedClubAData's comment) — its
        // absence here can ONLY be explained by the wipe, not by ordinary snapshot-diff, so this
        // is the assertion that actually pins the wipe rather than incidentally passing because a
        // non-empty club B pull would have cleaned up the diffable tables on its own.
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<SeasonArchive>()).isEmpty,
                      "club A's season archive is untouched by ordinary diff — only the wipe removes it")
        XCTAssertEqual(marker.clubId, clubB)
    }

    /// A club switch must discard an un-synced local edit, never push it to the new club — "flush
    /// the outbox before the first pull" from the plan. If the wipe ran, the outbox is empty by
    /// the time `SyncPusher` looks, so it makes no request at all; only the pull's GETs happen.
    func testOutboxNeverPushedAcrossClubSwitch() async throws {
        let ctx = try makeContext()
        let (athlete, _, _) = seedClubAData(in: ctx)
        ctx.insert(PendingChange(entityType: "Athlete", entityId: athlete.id, operation: .update))
        try ctx.save()

        let log = CallLog()
        StubURLProtocol.handler = { request in
            log.record("\(request.httpMethod ?? "") \(request.url?.path ?? "")")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(self.emptyPage().utf8))
        }

        let marker = InMemoryClubMarker(clubA)
        let coordinator = SyncCoordinator(context: ctx, client: client(), tokenProvider: { "tok" },
                                          clubIdProvider: { clubB }, clubMarker: marker)
        await coordinator.syncNow()

        XCTAssertTrue(log.paths.allSatisfy { $0.hasPrefix("GET") },
                      "the push half must have nothing to push once the club-change wipe drains the outbox — saw \(log.paths)")
    }

    /// A brand-new coach's first-ever sync (no prior club to protect data from) must not wipe.
    func testFirstSyncAfterApprovalDoesNotWipe() async throws {
        let ctx = try makeContext()

        let ts = "2026-06-01T10:00:00Z"
        let clubAAthlete = "{\"id\":\"\(clubAAthleteID)\",\"firstName\":\"ClubA\",\"lastName\":\"Athlete\",\"dateOfBirth\":\"2010-06-15\",\"gender\":null,\"guardianName\":null,\"guardianPhone\":null,\"guardianEmail\":null,\"active\":true,\"developmentStage\":\"INITIATION\",\"createdAt\":\"\(ts)\",\"updatedAt\":\"\(ts)\"}"
        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let json: String
            if path == "/api/athletes" { json = self.page(clubAAthlete) }
            else if path == "/api/coaches" || path == "/api/teams" || path == "/api/sessions" { json = self.emptyPage() }
            else { json = "[]" }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let marker = InMemoryClubMarker(nil)
        let coordinator = SyncCoordinator(context: ctx, client: client(), tokenProvider: { "tok" },
                                          clubIdProvider: { clubA }, clubMarker: marker)
        await coordinator.syncNow()

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Athlete>()).count, 1, "the pull should proceed normally")
        XCTAssertEqual(marker.clubId, clubA, "marker now tracks club A for future comparisons")
    }
}
