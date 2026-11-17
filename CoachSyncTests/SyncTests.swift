import XCTest
import SwiftData
@testable import CoachSync

/// Stage 2 read-sync: enum/date translation, DTO→model mapping, and an end-to-end snapshot
/// pull through a stubbed client. Reuses `StubURLProtocol` from AuthTests.

private let coachID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
private let athleteID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
private let teamID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
private let sessionID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
private let blockID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!

@MainActor
private func makeContext() throws -> ModelContext {
    let config = ModelConfiguration(schema: CoachSyncContainer.schema, isStoredInMemoryOnly: true)
    return ModelContext(try ModelContainer(for: CoachSyncContainer.schema, configurations: config))
}

// MARK: - Enum + date translation

final class SyncTranslationTests: XCTestCase {

    func testBackendEnumNamesMapToAppCases() {
        XCTAssertEqual(SyncEnum.blockType("PADDLE_PYRAMID"), .paddlePyramid)
        XCTAssertEqual(SyncEnum.blockType("RUN_INTERVALS"), .runIntervals)
        XCTAssertEqual(SyncEnum.trainingZone("AN_MIX"), .anMix)
        XCTAssertEqual(SyncEnum.trainingZone("GA_1"), .ga1)
        XCTAssertNil(SyncEnum.trainingZone(nil))
        XCTAssertEqual(SyncEnum.sessionStatus("CANCELLED"), .cancelled)
        XCTAssertEqual(SyncEnum.attendanceStatus("EXCUSED"), .excused)
        XCTAssertEqual(SyncEnum.repStatus("DNF"), .dnf)
        XCTAssertEqual(SyncEnum.gender("MALE"), .male)
        XCTAssertEqual(SyncEnum.stage("REFINEMENT"), .refinement)
    }

    func testLocalDateParsesToCalendarDay() {
        let comps = Calendar.current.dateComponents([.year, .month, .day],
                                                    from: SyncDate.localDate("2010-06-15"))
        XCTAssertEqual(comps.year, 2010)
        XCTAssertEqual(comps.month, 6)
        XCTAssertEqual(comps.day, 15)
    }

    func testLocalDateTimeWireIsUTCSoItIsZoneStable() {
        // 1_700_000_000 = 2023-11-14T22:13:20Z. Session start/end must serialize in UTC (not the
        // device's local wall-clock) so a cross-zone pull reconstructs the same absolute instant.
        // Asserting the exact UTC string makes this independent of the test machine's time zone.
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(SyncDate.localDateTimeString(d), "2023-11-14T22:13:20")
        XCTAssertEqual(SyncDate.localDateTime("2023-11-14T22:13:20"), d)
    }

    func testReverseEnumNamesAndRoundTrip() {
        XCTAssertEqual(SyncEnum.name(BlockType.paddlePyramid), "PADDLE_PYRAMID")
        XCTAssertEqual(SyncEnum.name(TrainingZone.anMix), "AN_MIX")
        XCTAssertEqual(SyncEnum.name(SessionStatus.open), "OPEN")          // not the "Scheduled" raw value
        XCTAssertEqual(SyncEnum.name(SessionStatus.completed), "COMPLETED")
        XCTAssertEqual(SyncEnum.name(AttendanceStatus.excused), "EXCUSED")
        XCTAssertEqual(SyncEnum.name(RepEntryStatus.dnf), "DNF")
        XCTAssertEqual(SyncEnum.name(Gender.male), "MALE")
        XCTAssertEqual(SyncEnum.name(DevelopmentStage.refinement), "REFINEMENT")
        XCTAssertNil(SyncEnum.name(nil as TrainingZone?))
        // Round-trip against the forward (backend-name → app-case) mappers.
        XCTAssertEqual(SyncEnum.name(SyncEnum.blockType("RUN_INTERVALS")), "RUN_INTERVALS")
        XCTAssertEqual(SyncEnum.sessionStatus(SyncEnum.name(SessionStatus.open)), .open)
    }

    func testReverseMapperBuildsBackendAthleteRequest() {
        let athlete = Athlete(firstName: "Ada", lastName: "Lovelace",
                              dateOfBirth: SyncDate.localDate("2010-06-15"), gender: .female)
        athlete.developmentStage = .acquisition
        athlete.isActive = false
        let dto = SyncPush.athleteRequest(athlete)
        XCTAssertEqual(dto.id, athlete.id)
        XCTAssertEqual(dto.gender, "FEMALE")
        XCTAssertEqual(dto.developmentStage, "ACQUISITION")
        XCTAssertEqual(dto.dateOfBirth, "2010-06-15")
        XCTAssertFalse(dto.active)
    }
}

// MARK: - DTO → model mapping

final class SyncMappingTests: XCTestCase {

    @MainActor
    func testUpsertAthleteMapsFieldsEnumsAndDates() throws {
        let ctx = try makeContext()
        let dto = AthleteDTO(
            id: athleteID, firstName: "Ada", lastName: "Lovelace", dateOfBirth: "2010-06-15",
            gender: "FEMALE", guardianName: "G", guardianPhone: nil, guardianEmail: nil,
            active: false, developmentStage: "ACQUISITION", createdAt: .now, updatedAt: .now)
        SyncMapping.upsertAthlete(dto, in: ctx)

        let athlete = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Athlete>()).first)
        XCTAssertEqual(athlete.id, athleteID)
        XCTAssertEqual(athlete.fullName, "Ada Lovelace")
        XCTAssertEqual(athlete.gender, .female)
        XCTAssertEqual(athlete.developmentStage, .acquisition)
        XCTAssertFalse(athlete.isActive)
    }

    @MainActor
    func testUpsertSessionResolvesCoachNameAndTeamLink() throws {
        let ctx = try makeContext()
        SyncMapping.upsertCoach(CoachDTO(id: coachID, name: "Pat", role: nil, nccpLevel: nil,
                                         colorHex: nil, createdAt: .now, updatedAt: .now), in: ctx)
        SyncMapping.upsertTeam(TeamDTO(id: teamID, teamName: "U14", teamDescription: nil,
                                       archived: false, createdAt: .now, updatedAt: .now), in: ctx)
        SyncMapping.upsertSession(SessionDTO(
            id: sessionID, sessionName: "Tuesday", scheduledDate: "2026-06-10",
            startTime: nil, endTime: nil, status: "COMPLETED", weatherNote: nil, teamNote: nil,
            sessionNote: nil, mfCue: nil, archived: false, coachId: coachID, teamId: teamID,
            createdAt: .now, updatedAt: .now), in: ctx)

        let session = try XCTUnwrap(try ctx.fetch(FetchDescriptor<CoachSession>()).first)
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.createdByCoachName, "Pat")   // coachId → denormalized name
        XCTAssertEqual(session.team?.id, teamID)
    }

    @MainActor
    /// A coach deleting their account changes the coach row, not the sessions they logged, so the
    /// session's own merge check would skip it and leave their real name showing.
    func testPullingAnAnonymizedCoachRenamesTheirUnchangedSession() throws {
        let ctx = try makeContext()
        let logged = Date(timeIntervalSince1970: 1_000)
        SyncMapping.upsertCoach(CoachDTO(id: coachID, name: "Alice", role: "Head", nccpLevel: nil,
                                         colorHex: nil, createdAt: logged, updatedAt: logged), in: ctx)
        let session = SessionDTO(
            id: sessionID, sessionName: "Tuesday", scheduledDate: "2026-06-10",
            startTime: nil, endTime: nil, status: "COMPLETED", weatherNote: nil, teamNote: nil,
            sessionNote: nil, mfCue: nil, archived: false, coachId: coachID, teamId: nil,
            createdAt: logged, updatedAt: logged)
        SyncMapping.upsertSession(session, in: ctx)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<CoachSession>()).first?.createdByCoachName, "Alice")

        let deleted = logged.addingTimeInterval(60)
        SyncMapping.upsertCoach(CoachDTO(id: coachID, name: "Former coach", role: nil, nccpLevel: nil,
                                         colorHex: nil, createdAt: logged, updatedAt: deleted), in: ctx)
        SyncMapping.upsertSession(session, in: ctx)

        let coach = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Coach>()).first)
        XCTAssertEqual(coach.name, "Former coach")
        XCTAssertNil(coach.role)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<CoachSession>()).first?.createdByCoachName, "Former coach")
    }

    func testUpsertSessionPreservesCoachNameWhenCoachUnresolved() throws {
        let ctx = try makeContext()
        let t1 = Date(timeIntervalSince1970: 1000), t2 = Date(timeIntervalSince1970: 2000)
        func session(updated: Date) -> SessionDTO {
            SessionDTO(id: sessionID, sessionName: "Tuesday", scheduledDate: "2026-06-10",
                       startTime: nil, endTime: nil, status: "COMPLETED", weatherNote: nil, teamNote: nil,
                       sessionNote: nil, mfCue: nil, archived: false, coachId: coachID, teamId: nil,
                       createdAt: .now, updatedAt: updated)
        }
        SyncMapping.upsertCoach(CoachDTO(id: coachID, name: "Pat", role: nil, nccpLevel: nil,
                                         colorHex: nil, createdAt: .now, updatedAt: .now), in: ctx)
        SyncMapping.upsertSession(session(updated: t1), in: ctx)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<CoachSession>()).first?.createdByCoachName, "Pat")

        // The coach is pending local deletion → existingCoach now returns nil. A newer pull of the same
        // session must NOT nil-out the attribution snapshot (it self-heals on a later pull).
        for coach in try ctx.fetch(FetchDescriptor<Coach>()) { ctx.delete(coach) }
        try ctx.save()
        SyncMapping.upsertSession(session(updated: t2), in: ctx)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<CoachSession>()).first?.createdByCoachName, "Pat",
                       "attribution must survive an unresolved (pending-deleted) coach")
    }

    @MainActor
    func testUpsertBlockCarriesServerUpdatedAt() throws {
        let ctx = try makeContext()
        SyncMapping.upsertSession(SessionDTO(
            id: sessionID, sessionName: "S", scheduledDate: "2026-06-10", startTime: nil, endTime: nil,
            status: "OPEN", weatherNote: nil, teamNote: nil, sessionNote: nil, mfCue: nil, archived: false,
            coachId: nil, teamId: nil, createdAt: .now, updatedAt: .now), in: ctx)
        let ts = Date(timeIntervalSince1970: 5000)
        SyncMapping.upsertBlock(BlockDTO(
            id: blockID, sessionId: sessionID, blockName: "B", blockType: "PADDLE_DISTANCE", sortOrder: 0,
            repetitionCount: 1, setCount: 1, targetDistanceMetres: nil, distanceKm: nil,
            restIntervalSeconds: nil, durationSeconds: nil, requiresTimeEntry: true, trainingZone: nil,
            drillName: nil, coachNote: nil, prescribedRepDurationsSec: [], updatedAt: ts), in: ctx)
        let block = try XCTUnwrap(try ctx.fetch(FetchDescriptor<SessionBlock>()).first)
        XCTAssertEqual(block.updatedAt, ts, "pulled block must carry the server updatedAt or LWW breaks for blocks")
    }

    @MainActor
    func testUpsertIsIdempotentById() throws {
        let ctx = try makeContext()
        SyncMapping.upsertTeam(TeamDTO(id: teamID, teamName: "U14", teamDescription: nil,
                                       archived: false, createdAt: .now,
                                       updatedAt: Date(timeIntervalSince1970: 1)), in: ctx)
        SyncMapping.upsertTeam(TeamDTO(id: teamID, teamName: "U16", teamDescription: nil,
                                       archived: true, createdAt: .now,
                                       updatedAt: Date(timeIntervalSince1970: 2)), in: ctx)

        let teams = try ctx.fetch(FetchDescriptor<Team>())
        XCTAssertEqual(teams.count, 1, "same id should upsert, not duplicate")
        XCTAssertEqual(teams.first?.teamName, "U16")
        XCTAssertTrue(teams.first?.isArchived == true)
    }

    // MARK: last-write-wins

    private func team(_ name: String, archived: Bool = false, updated: Date) -> TeamDTO {
        TeamDTO(id: teamID, teamName: name, teamDescription: nil, archived: archived,
                createdAt: Date(timeIntervalSince1970: 0), updatedAt: updated)
    }

    @MainActor
    func testLWWNewerServerWinsOlderLoses() throws {
        let ctx = try makeContext()
        let t1 = Date(timeIntervalSince1970: 1000), t2 = Date(timeIntervalSince1970: 2000)
        SyncMapping.upsertTeam(team("First", updated: t1), in: ctx)
        SyncMapping.upsertTeam(team("Newer", updated: t2), in: ctx)            // newer → overwrite
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Team>()).first?.teamName, "Newer")
        SyncMapping.upsertTeam(team("Older", updated: t1), in: ctx)            // older → ignored
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Team>()).first?.teamName, "Newer")
    }

    @MainActor
    func testLWWPendingOutboxProtectsLocalEdit() throws {
        let ctx = try makeContext()
        let t1 = Date(timeIntervalSince1970: 1000), t2 = Date(timeIntervalSince1970: 2000)
        SyncMapping.upsertTeam(team("Local", updated: t1), in: ctx)
        // newer server, but an un-pushed local change for this id → local wins
        SyncMapping.upsertTeam(team("ServerNewer", updated: t2), in: ctx, pending: [teamID])
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Team>()).first?.teamName, "Local")
    }

    @MainActor
    func testPendingDeleteIsNotResurrected() throws {
        let ctx = try makeContext()
        // No local record; the server has one; but a pending entry marks a local delete → skip create.
        SyncMapping.upsertTeam(team("Ghost", updated: .now), in: ctx, pending: [teamID])
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<Team>()).isEmpty)
    }
}

// MARK: - Snapshot pull (end-to-end through a stubbed client)

final class SyncServiceTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func page(_ item: String) -> String {
        "{\"content\":[\(item)],\"page\":{\"size\":500,\"number\":0,\"totalElements\":1,\"totalPages\":1}}"
    }
    private func emptyPage() -> String {
        "{\"content\":[],\"page\":{\"size\":500,\"number\":0,\"totalElements\":0,\"totalPages\":1}}"
    }
    private func client() -> BackendClient {
        BackendClient(baseURL: URL(string: "http://test.local")!, session: StubURLProtocol.session())
    }

    @MainActor
    func testPullMergesClubIntoLiveStore() async throws {
        let ts = "2026-06-01T10:00:00Z"
        let coach = "{\"id\":\"\(coachID)\",\"name\":\"Pat\",\"role\":null,\"nccpLevel\":null,\"colorHex\":null,\"createdAt\":\"\(ts)\",\"updatedAt\":\"\(ts)\"}"
        let athlete = "{\"id\":\"\(athleteID)\",\"firstName\":\"Ada\",\"lastName\":\"L\",\"dateOfBirth\":\"2010-06-15\",\"gender\":\"FEMALE\",\"guardianName\":null,\"guardianPhone\":null,\"guardianEmail\":null,\"active\":true,\"developmentStage\":\"INITIATION\",\"createdAt\":\"\(ts)\",\"updatedAt\":\"\(ts)\"}"
        let team = "{\"id\":\"\(teamID)\",\"teamName\":\"U14\",\"teamDescription\":null,\"archived\":false,\"createdAt\":\"\(ts)\",\"updatedAt\":\"\(ts)\"}"
        let session = "{\"id\":\"\(sessionID)\",\"sessionName\":\"Tue\",\"scheduledDate\":\"2026-06-10\",\"startTime\":null,\"endTime\":null,\"status\":\"COMPLETED\",\"weatherNote\":null,\"teamNote\":null,\"sessionNote\":null,\"mfCue\":null,\"archived\":false,\"coachId\":\"\(coachID)\",\"teamId\":\"\(teamID)\",\"createdAt\":\"\(ts)\",\"updatedAt\":\"\(ts)\"}"
        let block = "[{\"id\":\"\(blockID)\",\"sessionId\":\"\(sessionID)\",\"blockName\":\"Paddle\",\"blockType\":\"PADDLE_DISTANCE\",\"sortOrder\":0,\"repetitionCount\":3,\"setCount\":1,\"targetDistanceMetres\":500,\"distanceKm\":null,\"restIntervalSeconds\":null,\"durationSeconds\":null,\"requiresTimeEntry\":true,\"trainingZone\":\"GA_1\",\"drillName\":null,\"coachNote\":null,\"prescribedRepDurationsSec\":[],\"updatedAt\":\"\(ts)\"}]"

        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let json: String
            if path.hasSuffix("/blocks") { json = block }
            else if path == "/api/coaches" { json = self.page(coach) }   // exact: sub-resource GETs
            else if path == "/api/athletes" { json = self.page(athlete) }  // (…/attendance, …/notes,
            else if path == "/api/teams" { json = self.page(team) }        //  …/assessments) must fall
            else if path == "/api/sessions" { json = self.page(session) }  //  through to the [] list
            else { json = "[]" }   // members / attendance / notes / performance / per-athlete domains
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let ctx = try makeContext()
        try await SyncService(client: client()).pull(into: ctx, token: "tok")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Athlete>()).count, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Team>()).count, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<CoachSession>()).count, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<SessionBlock>()).count, 1)
        // Pulled rows are committed via a raw save on a private context — they must NOT enqueue outbox
        // entries (else the next push would echo the whole snapshot back to the server).
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<PendingChange>()).isEmpty, "a pull must not enqueue")
    }

    @MainActor
    func testSnapshotDiffDeletesAbsentButKeepsPending() async throws {
        let ctx = try makeContext()
        let keepID = UUID(), dropID = UUID(), otherID = UUID()
        let keep = Athlete(firstName: "Keep", lastName: "Me", dateOfBirth: .distantPast)
        keep.id = keepID
        ctx.insert(keep)
        let drop = Athlete(firstName: "Drop", lastName: "Me", dateOfBirth: .distantPast)
        drop.id = dropID
        ctx.insert(drop)
        // The kept athlete has an un-pushed local create — it must survive the diff.
        ctx.insert(PendingChange(entityType: "Athlete", entityId: keepID, operation: .insert))
        try ctx.save()

        // Server returns a NON-empty snapshot (one athlete the device lacks) so the diff runs — a
        // fully-empty snapshot is treated as a glitch and the diff is skipped (mass-delete guard).
        let ts = "2026-06-01T10:00:00Z"
        let other = "{\"id\":\"\(otherID)\",\"firstName\":\"Other\",\"lastName\":\"One\",\"dateOfBirth\":\"2014-01-01\",\"gender\":null,\"guardianName\":null,\"guardianPhone\":null,\"guardianEmail\":null,\"active\":true,\"developmentStage\":\"INITIATION\",\"createdAt\":\"\(ts)\",\"updatedAt\":\"\(ts)\"}"
        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let json: String
            if path == "/api/athletes" { json = self.page(other) }
            else if path == "/api/coaches" || path == "/api/teams" || path == "/api/sessions" { json = self.emptyPage() }
            else { json = "[]" }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        try await SyncService(client: client()).pull(into: ctx, token: "tok")

        let ids = Set(try ctx.fetch(FetchDescriptor<Athlete>()).map(\.id))
        XCTAssertTrue(ids.contains(keepID), "pending athlete survives the diff")
        XCTAssertTrue(ids.contains(otherID), "server athlete is pulled in")
        XCTAssertFalse(ids.contains(dropID), "absent, non-pending athlete is diff-deleted")
    }

    /// The mass-delete guard. A wholly empty snapshot means a glitch (wrong club resolution, a
    /// backend/DB hiccup), not a real wipe — running the diff then would delete the coach's entire
    /// roster on every device. Implemented at `SyncService.pull`; this pins it.
    @MainActor
    func testEmptyServerSnapshotSkipsDiffAndPreservesLocalData() async throws {
        let ctx = try makeContext()
        let athlete = Athlete(firstName: "Keep", lastName: "Me", dateOfBirth: .distantPast)
        let team = Team(teamName: "U14")
        let session = CoachSession(sessionName: "Tue", scheduledDate: .now)
        ctx.insert(athlete); ctx.insert(team); ctx.insert(session)
        let block = SessionBlock(blockName: "P", blockType: .paddleDistance, sortOrder: 0, session: session)
        ctx.insert(block)
        ctx.insert(Coach(name: "Pat"))
        try ctx.save()   // raw save: seeds the store without enqueueing any outbox rows

        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let topLevel = ["/api/coaches", "/api/athletes", "/api/teams", "/api/sessions"]
            let json = topLevel.contains(path) ? self.emptyPage() : "[]"
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        try await SyncService(client: client()).pull(into: ctx, token: "tok")

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Athlete>()).count, 1, "roster survives an empty snapshot")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Team>()).count, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<CoachSession>()).count, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<SessionBlock>()).count, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Coach>()).count, 1)
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<PendingChange>()).isEmpty, "a pull must not enqueue")
    }

    /// The diff only runs once *every* GET has succeeded, so a failure part-way through a pull must
    /// neither delete anything nor commit a partial snapshot. Boathouse Wi-Fi plus a free-tier
    /// backend makes this the most common real-world path.
    @MainActor
    func testMidPullFailureCommitsNothingAndDeletesNothing() async throws {
        let ctx = try makeContext()
        let local = Athlete(firstName: "Local", lastName: "Only", dateOfBirth: .distantPast)
        ctx.insert(local)
        try ctx.save()

        let ts = "2026-06-01T10:00:00Z"
        let serverAthlete = "{\"id\":\"\(athleteID)\",\"firstName\":\"Ada\",\"lastName\":\"L\",\"dateOfBirth\":\"2010-06-15\",\"gender\":null,\"guardianName\":null,\"guardianPhone\":null,\"guardianEmail\":null,\"active\":true,\"developmentStage\":\"INITIATION\",\"createdAt\":\"\(ts)\",\"updatedAt\":\"\(ts)\"}"
        let serverSession = "{\"id\":\"\(sessionID)\",\"sessionName\":\"Tue\",\"scheduledDate\":\"2026-06-10\",\"startTime\":null,\"endTime\":null,\"status\":\"COMPLETED\",\"weatherNote\":null,\"teamNote\":null,\"sessionNote\":null,\"mfCue\":null,\"archived\":false,\"coachId\":null,\"teamId\":null,\"createdAt\":\"\(ts)\",\"updatedAt\":\"\(ts)\"}"

        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            // Every top-level GET succeeds; a sub-resource GET fails mid-pull.
            if path.hasSuffix("/blocks") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            let json: String
            if path == "/api/athletes" { json = self.page(serverAthlete) }
            else if path == "/api/sessions" { json = self.page(serverSession) }
            else if path == "/api/coaches" || path == "/api/teams" { json = self.emptyPage() }
            else { json = "[]" }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        do {
            try await SyncService(client: client()).pull(into: ctx, token: "tok")
            XCTFail("expected the mid-pull GET failure to propagate")
        } catch BackendError.http(500) {
            // expected
        }

        let athletes = try ctx.fetch(FetchDescriptor<Athlete>())
        XCTAssertEqual(athletes.count, 1, "no partial commit: the server athlete never landed")
        XCTAssertEqual(athletes.first?.firstName, "Local", "the local-only athlete was not diff-deleted")
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<CoachSession>()).isEmpty, "no partial commit")
    }

    /// Attendance and performance merge by natural key — the app and the backend mint different ids
    /// for them — so a matching bug duplicates rows on *every* sync cycle, compounding silently and
    /// corrupting training load and insight signals. Pull the identical snapshot twice.
    @MainActor
    func testRepeatedPullDoesNotDuplicateNaturalKeyLeaves() async throws {
        let ctx = try makeContext()
        let ts = "2026-06-01T10:00:00Z"
        let athlete = "{\"id\":\"\(athleteID)\",\"firstName\":\"Ada\",\"lastName\":\"L\",\"dateOfBirth\":\"2010-06-15\",\"gender\":null,\"guardianName\":null,\"guardianPhone\":null,\"guardianEmail\":null,\"active\":true,\"developmentStage\":\"INITIATION\",\"createdAt\":\"\(ts)\",\"updatedAt\":\"\(ts)\"}"
        let session = "{\"id\":\"\(sessionID)\",\"sessionName\":\"Tue\",\"scheduledDate\":\"2026-06-10\",\"startTime\":null,\"endTime\":null,\"status\":\"COMPLETED\",\"weatherNote\":null,\"teamNote\":null,\"sessionNote\":null,\"mfCue\":null,\"archived\":false,\"coachId\":null,\"teamId\":null,\"createdAt\":\"\(ts)\",\"updatedAt\":\"\(ts)\"}"
        let block = "[{\"id\":\"\(blockID)\",\"sessionId\":\"\(sessionID)\",\"blockName\":\"Paddle\",\"blockType\":\"PADDLE_DISTANCE\",\"sortOrder\":0,\"repetitionCount\":2,\"setCount\":1,\"targetDistanceMetres\":500,\"distanceKm\":null,\"restIntervalSeconds\":null,\"durationSeconds\":null,\"requiresTimeEntry\":true,\"trainingZone\":\"GA_1\",\"drillName\":null,\"coachNote\":null,\"prescribedRepDurationsSec\":[],\"updatedAt\":\"\(ts)\"}]"
        let attendance = "[{\"id\":\"\(UUID())\",\"athleteId\":\"\(athleteID)\",\"status\":\"PRESENT\",\"absenceReason\":null,\"updatedAt\":\"\(ts)\"}]"

        // Each pull re-mints the leaf ids (as a real backend round-trip may), so only the natural
        // key can prevent duplicates. `repOneMs` and `leafTimestamp` vary per pull to exercise the
        // LWW boundary as well.
        nonisolated(unsafe) var repOneMs = 90_000
        nonisolated(unsafe) var leafTimestamp = "2026-06-02T10:00:00Z"
        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let performance = "[{\"id\":\"\(UUID())\",\"athleteId\":\"\(athleteID)\",\"repNumber\":1,\"recordedTimeMs\":\(repOneMs),\"status\":\"COMPLETE\",\"updatedAt\":\"\(leafTimestamp)\"},{\"id\":\"\(UUID())\",\"athleteId\":\"\(athleteID)\",\"repNumber\":2,\"recordedTimeMs\":91000,\"status\":\"COMPLETE\",\"updatedAt\":\"\(leafTimestamp)\"}]"
            let json: String
            if path.hasSuffix("/blocks") { json = block }
            else if path.hasSuffix("/attendance") { json = attendance }
            else if path.hasSuffix("/performance") { json = performance }
            else if path == "/api/athletes" { json = self.page(athlete) }
            else if path == "/api/sessions" { json = self.page(session) }
            else if path == "/api/coaches" || path == "/api/teams" { json = self.emptyPage() }
            else { json = "[]" }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        try await SyncService(client: client()).pull(into: ctx, token: "tok")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<AttendanceRecord>()).count, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<PerformanceRecord>()).count, 2)

        // Second pull, identical timestamp: no duplicates, and LWW keeps the local value on a tie
        // (the merge skips when the server's `updatedAt` is not strictly newer).
        repOneMs = 95_000
        try await SyncService(client: client()).pull(into: ctx, token: "tok")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<AttendanceRecord>()).count, 1,
                       "one AttendanceRecord per (session, athlete) — not one per pull")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<PerformanceRecord>()).count, 2,
                       "one PerformanceRecord per (block, athlete, rep) — not one per pull")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<PerformanceRecord>())
                        .first(where: { $0.repNumber == 1 })?.recordedTimeMs, 90_000,
                       "an equal updatedAt is not newer — LWW keeps the local value")

        // Third pull, strictly newer timestamp: the existing slot updates in place, still no dupes.
        leafTimestamp = "2026-06-03T10:00:00Z"
        try await SyncService(client: client()).pull(into: ctx, token: "tok")
        let reps = try ctx.fetch(FetchDescriptor<PerformanceRecord>())
        XCTAssertEqual(reps.count, 2, "updating a rep must not insert a second slot for it")
        XCTAssertEqual(reps.first(where: { $0.repNumber == 1 })?.recordedTimeMs, 95_000,
                       "a newer server timestamp updates the existing slot in place")
    }
}

// MARK: - Save chokepoint / outbox (Stage 3b)

@MainActor
final class SyncStoreTests: XCTestCase {

    func testInsertEnqueuesStampsAndSkipsSeasonArchive() throws {
        let ctx = try makeContext()
        let before = Date()
        let athlete = Athlete(firstName: "Ada", lastName: "L", dateOfBirth: .distantPast)
        ctx.insert(athlete)
        // SeasonArchive is app-only and must never enqueue an outbox row.
        ctx.insert(SeasonArchive(seasonYear: 2025, totalAthletes: 1, totalSessions: 1, totalKm: 1))
        try SyncStore.save(ctx)

        let changes = try ctx.fetch(FetchDescriptor<PendingChange>())
        XCTAssertEqual(changes.count, 1, "only the Athlete should enqueue, not SeasonArchive")
        XCTAssertEqual(changes.first?.entityType, "Athlete")
        XCTAssertEqual(changes.first?.entityId, athlete.id)
        XCTAssertEqual(changes.first?.operation, .insert)
        XCTAssertGreaterThanOrEqual(athlete.updatedAt, before, "updatedAt stamped on insert")
    }

    func testChangeEnqueuesUpdate() throws {
        let ctx = try makeContext()
        let team = Team(teamName: "U14")
        ctx.insert(team)
        try SyncStore.save(ctx)

        team.teamName = "U16"
        try SyncStore.save(ctx)

        let updates = try ctx.fetch(FetchDescriptor<PendingChange>()).filter { $0.operation == .update }
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.first?.entityType, "Team")
        XCTAssertEqual(updates.first?.entityId, team.id)
    }

    /// Characterization test for a KNOWN LIMITATION surfaced by code review: SwiftData marks a
    /// parent "changed" when a child is inserted (its inverse to-many mutates), so the chokepoint
    /// also stamps the parent's `updatedAt` and enqueues a redundant parent push. Harmless for a
    /// single-coach club, but across coaches a child insert (e.g. logging attendance) can advance a
    /// session's LWW timestamp and revert a concurrent edit to that session's own fields. The proper
    /// fix (enqueue only on a real attribute change) is a tracked follow-up; this test pins the
    /// current behavior so a future fix is noticed here.
    func testChildInsertAlsoEnqueuesParent_knownLimitation() throws {
        let ctx = try makeContext()
        let session = CoachSession(sessionName: "S", scheduledDate: .now)
        ctx.insert(session)
        try SyncStore.save(ctx)
        for change in try ctx.fetch(FetchDescriptor<PendingChange>()) { ctx.delete(change) }
        try ctx.save()

        let block = SessionBlock(blockName: "B", blockType: .paddleDistance, sortOrder: 0, session: session)
        ctx.insert(block)
        try SyncStore.save(ctx)

        let parentChanges = try ctx.fetch(FetchDescriptor<PendingChange>())
            .filter { $0.entityType == "CoachSession" }
        XCTAssertEqual(parentChanges.count, 1,
                       "child insert currently also enqueues its parent (known LWW-churn limitation)")
    }

    func testDeleteEnqueuesDelete() throws {
        let ctx = try makeContext()
        let team = Team(teamName: "U14")
        let teamId = team.id
        ctx.insert(team)
        try SyncStore.save(ctx)

        ctx.delete(team)
        try SyncStore.save(ctx)

        let deletes = try ctx.fetch(FetchDescriptor<PendingChange>()).filter { $0.operation == .delete }
        XCTAssertEqual(deletes.count, 1)
        XCTAssertEqual(deletes.first?.entityType, "Team")
        XCTAssertEqual(deletes.first?.entityId, teamId)
    }
}

// MARK: - Pusher (outbox drain through a stubbed client)

/// Thread-safe call recorder for the stubbed URL protocol.
private final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var paths: [String] = []
    func record(_ path: String) { lock.lock(); paths.append(path); lock.unlock() }
}

@MainActor
final class SyncPusherTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func client() -> BackendClient {
        BackendClient(baseURL: URL(string: "http://test.local")!, session: StubURLProtocol.session())
    }

    func testPushesParentBeforeChildAndCoalesces() async throws {
        let ctx = try makeContext()
        let athlete = Athlete(firstName: "Ada", lastName: "L", dateOfBirth: .distantPast)
        ctx.insert(athlete)
        let session = CoachSession(sessionName: "Tue", scheduledDate: .now)
        ctx.insert(session)
        let block = SessionBlock(blockName: "P", blockType: .paddleDistance, sortOrder: 0, session: session)
        ctx.insert(block)
        try SyncStore.save(ctx)             // 3 inserts enqueued
        athlete.firstName = "Ada B"
        try SyncStore.save(ctx)             // + an athlete update (coalesces with its insert)

        let log = CallLog()
        StubURLProtocol.handler = { request in
            log.record(request.url?.path ?? "")
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }
        try await SyncPusher(client: client(), token: "tok", context: ctx).push()

        // Parent → child order; the athlete's insert+update collapse to one POST.
        XCTAssertEqual(log.paths, [
            "/api/athletes",
            "/api/sessions",
            "/api/sessions/\(session.id.uuidString)/blocks",
        ])
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<PendingChange>()).isEmpty, "outbox drained")
    }

    func testDeleteTolerates404AndClearsOutbox() async throws {
        let ctx = try makeContext()
        let team = Team(teamName: "U14")
        ctx.insert(team)
        try SyncStore.save(ctx)
        ctx.delete(team)
        try SyncStore.save(ctx)             // record gone → DELETE

        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        try await SyncPusher(client: client(), token: "tok", context: ctx).push()

        XCTAssertTrue(try ctx.fetch(FetchDescriptor<PendingChange>()).isEmpty,
                      "404 on a delete = already cascaded; the rows are cleared")
    }

    /// A record that still exists but can't be sent (here a block whose session link is gone) must
    /// stay queued and be reported — never fall through to the delete path as if it were deleted.
    func testExistingRecordWithMissingParentIsLeftPendingNotDeleted() async throws {
        let ctx = try makeContext()
        let session = CoachSession(sessionName: "Tue", scheduledDate: .now)
        let block = SessionBlock(blockName: "P", blockType: .paddleDistance, sortOrder: 0, session: session)
        ctx.insert(session); ctx.insert(block)
        try ctx.save()
        block.session = nil
        try SyncStore.save(ctx)

        let log = CallLog()
        StubURLProtocol.handler = { request in
            log.record("\(request.httpMethod ?? "") \(request.url?.path ?? "")")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }
        let stuck = try await SyncPusher(client: client(), token: "tok", context: ctx).push()

        XCTAssertFalse(log.paths.contains { $0.hasPrefix("DELETE") }, "an existing block must never be deleted: \(log.paths)")
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<PendingChange>()).contains { $0.entityId == block.id },
                      "the block's change stays queued for a later run")
        XCTAssertGreaterThanOrEqual(stuck, 1, "and is reported rather than silently held")
    }

    func testReauthRequiredOn401LeavesOutbox() async throws {
        let ctx = try makeContext()
        ctx.insert(Team(teamName: "U14"))
        try SyncStore.save(ctx)

        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        do {
            try await SyncPusher(client: client(), token: "tok", context: ctx).push()
            XCTFail("expected reauthRequired")
        } catch SyncPusher.PushError.reauthRequired {
            // expected
        }
        XCTAssertFalse(try ctx.fetch(FetchDescriptor<PendingChange>()).isEmpty, "401 leaves the outbox pending")
    }

    func testClientRejection400LeavesOutboxAndReportsStuckCount() async throws {
        // A definite backend rejection (e.g. failed validation) must not be treated as merely
        // transient: the row stays pending (data isn't dropped) AND the caller is told it's stuck,
        // so the coach can be warned instead of the sync silently reporting a bare "success".
        let ctx = try makeContext()
        ctx.insert(Team(teamName: "U14"))
        try SyncStore.save(ctx)

        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let stuckCount = try await SyncPusher(client: client(), token: "tok", context: ctx).push()

        XCTAssertEqual(stuckCount, 1)
        XCTAssertFalse(try ctx.fetch(FetchDescriptor<PendingChange>()).isEmpty,
                        "a 400 leaves the row pending rather than dropping the data")
    }

    /// A transport failure (offline, TLS, DNS) is transient: the op stays pending for the next run
    /// and is *not* reported as stuck. `handler = nil` makes the stub fail the request outright.
    func testTransportFailureLeavesOpPendingAndNotStuck() async throws {
        let ctx = try makeContext()
        ctx.insert(Team(teamName: "U14"))
        try SyncStore.save(ctx)

        StubURLProtocol.handler = nil   // → URLError, surfaced as BackendError.transport
        let stuckCount = try await SyncPusher(client: client(), token: "tok", context: ctx).push()

        XCTAssertEqual(stuckCount, 0, "offline is transient, not stuck")
        XCTAssertFalse(try ctx.fetch(FetchDescriptor<PendingChange>()).isEmpty,
                       "the op stays queued for the next run")
    }

    /// Mixed outcomes in one batch: the succeeded op's rows clear, the failed op stays pending, and
    /// the replay sends *only* the failed op. Re-sending an already-created entity would 409, and a
    /// 409 drops the rows — silently discarding the coach's coalesced edits.
    func testPartialBatchClearsSucceededOpAndReplaysOnlyTheFailedOne() async throws {
        let ctx = try makeContext()
        ctx.insert(Athlete(firstName: "Ada", lastName: "L", dateOfBirth: .distantPast))
        ctx.insert(Team(teamName: "U14"))
        try SyncStore.save(ctx)   // Athlete (rank 1) pushes before Team (rank 2)

        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let status = path == "/api/teams" ? 500 : 201   // team fails transiently
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }
        let stuckCount = try await SyncPusher(client: client(), token: "tok", context: ctx).push()

        XCTAssertEqual(stuckCount, 0, "a 500 is transient, not a definitive client rejection")
        let pending = try ctx.fetch(FetchDescriptor<PendingChange>())
        XCTAssertEqual(pending.map(\.entityType), ["Team"], "only the failed op stays queued")

        // Replay against a healthy backend: the athlete must NOT be re-POSTed.
        let log = CallLog()
        StubURLProtocol.handler = { request in
            log.record(request.url?.path ?? "")
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }
        try await SyncPusher(client: client(), token: "tok", context: ctx).push()

        XCTAssertEqual(log.paths, ["/api/teams"], "the replay resends only the previously failed op")
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<PendingChange>()).isEmpty, "outbox drained")
    }

    /// Regression: a 401 landing mid-batch must **commit** the outbox rows already cleared by the
    /// ops that succeeded before it.
    ///
    /// `execute` throws `reauthRequired` on a 401, so a trailing `context.save()` never ran — the
    /// succeeded ops' `PendingChange` deletions stayed staged-but-unsaved. The live context still
    /// *reports* them as gone, which is why this test reloads a fresh `ModelContext` over the same
    /// container: that reads committed state only, exactly as an app relaunch does. Pre-fix, the
    /// athlete's rows resurrect there, the retry re-POSTs an entity the backend already has, and the
    /// resulting 409 drops them — silent loss of the coach's coalesced edits. The 30-day JWT makes a
    /// mid-sync expiry a matter of when, not if. Fixed by saving in a `defer`.
    func test401MidBatchCommitsClearedRowsAcrossAContextReload() async throws {
        let config = ModelConfiguration(schema: CoachSyncContainer.schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: CoachSyncContainer.schema, configurations: config)
        let ctx = ModelContext(container)
        ctx.insert(Athlete(firstName: "Ada", lastName: "L", dateOfBirth: .distantPast))
        ctx.insert(Team(teamName: "U14"))
        try SyncStore.save(ctx)   // Athlete (rank 1) pushes before Team (rank 2)

        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let status = path == "/api/teams" ? 401 : 201   // token expires mid-batch
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }
        do {
            try await SyncPusher(client: client(), token: "tok", context: ctx).push()
            XCTFail("expected reauthRequired")
        } catch SyncPusher.PushError.reauthRequired {
            // expected
        }

        // A fresh context over the same container sees only what was committed — the app-relaunch view.
        let reloaded = ModelContext(container)
        let pending = try reloaded.fetch(FetchDescriptor<PendingChange>())
        XCTAssertEqual(Set(pending.map(\.entityType)), ["Team"],
                       "the succeeded athlete's outbox rows must be committed as cleared, not resurrect")

        // After a fresh sign-in the replay must not re-POST the athlete the backend already has.
        let log = CallLog()
        StubURLProtocol.handler = { request in
            log.record(request.url?.path ?? "")
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }
        try await SyncPusher(client: client(), token: "tok2", context: reloaded).push()

        XCTAssertEqual(log.paths, ["/api/teams"], "no duplicate POST of the already-landed athlete")
        XCTAssertTrue(try reloaded.fetch(FetchDescriptor<PendingChange>()).isEmpty, "outbox drained")
    }

    func testMembershipLeavePutSortsBeforeRejoinPost() async throws {
        let ctx = try makeContext()
        let team = Team(teamName: "T")
        let a1 = Athlete(firstName: "A", lastName: "1", dateOfBirth: .distantPast)
        let a2 = Athlete(firstName: "A", lastName: "2", dateOfBirth: .distantPast)
        ctx.insert(team); ctx.insert(a1); ctx.insert(a2)
        let m1 = TeamMembership(athlete: a1, team: team)
        ctx.insert(m1)
        try SyncStore.save(ctx)
        for change in try ctx.fetch(FetchDescriptor<PendingChange>()) { ctx.delete(change) }
        try ctx.save()

        // Leave m1 (update → PUT) and re-add a2 as m2 (insert → POST) in one batch.
        m1.leftDate = Date()
        ctx.insert(TeamMembership(athlete: a2, team: team))
        try SyncStore.save(ctx)

        let log = CallLog()
        StubURLProtocol.handler = { request in
            log.record((request.httpMethod ?? "") + " " + (request.url?.path ?? ""))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }
        try await SyncPusher(client: client(), token: "tok", context: ctx).push()

        let memberCalls = log.paths.filter { $0.contains("/members") }
        XCTAssertEqual(memberCalls.count, 2)
        XCTAssertTrue(memberCalls[0].hasPrefix("PUT"), "the leave PUT must precede the re-join POST")
        XCTAssertTrue(memberCalls[1].hasPrefix("POST"))
    }
}

// MARK: - Coordinator (push-then-pull status handling)

@MainActor
final class SyncCoordinatorTests: XCTestCase {

    override func tearDown() { StubURLProtocol.handler = nil }

    private func client() -> BackendClient {
        BackendClient(baseURL: URL(string: "http://test.local")!, session: StubURLProtocol.session())
    }

    /// A 401 from the PULL half must surface as needsReauth, not the generic "check connection"
    /// failure (the pusher already maps its own 401 to reauthRequired). Empty outbox → the push half
    /// is a no-op, so the 401 comes from the pull.
    func testPullUnauthorizedSurfacesNeedsReauth() async throws {
        let ctx = try makeContext()
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        // In-memory marker: an unrelated test must never touch real UserDefaults (the production
        // default), which could otherwise pick up a stale clubId across test runs and trigger the
        // slice-6 wipe path spuriously here.
        let coordinator = SyncCoordinator(context: ctx, client: client(), tokenProvider: { "tok" },
                                          clubMarker: InMemoryClubMarker())
        await coordinator.syncNow()
        XCTAssertEqual(coordinator.status, .needsReauth)
    }
}
