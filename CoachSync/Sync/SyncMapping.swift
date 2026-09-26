/// Maps backend DTOs onto SwiftData `@Model`s for the sync pull (Stage 3c, into the LIVE store).
///
/// Merge is **last-write-wins**: a server record overwrites the local one only when it is strictly
/// newer (`server.updatedAt > local.updatedAt`) AND the local record has no pending outbox entry —
/// an un-pushed local edit (or delete) always wins, and the pusher reconciles it. A record absent
/// locally is created, unless a pending entry says it was locally deleted (don't resurrect it).
///
/// Two parity gaps this layer bridges (from the 2B audit):
/// • Enums — the app's raw values are display strings ("Paddle Distance"), the backend sends Java
///   enum *names* ("PADDLE_DISTANCE"), so `init(rawValue:)` can't be used.
/// • Attribution — the backend keys a session/note to a `coachId`; the app shows a denormalized
///   `createdByCoachName`, resolved here from the already-upserted `Coach`.
///
/// Leaf records (attendance, performance) merge by **natural key** (session+athlete, block+athlete+
/// rep), not id — the app and backend each mint their own ids for them.

import Foundation
import SwiftData

/// Translates backend enum names → the app's display-string enum cases.
enum SyncEnum {
    static func gender(_ s: String?) -> Gender? {
        switch s { case "MALE": return .male; case "FEMALE": return .female; default: return nil }
    }

    static func stage(_ s: String) -> DevelopmentStage {
        switch s {
        case "ACQUISITION": return .acquisition
        case "CONSOLIDATION": return .consolidation
        case "REFINEMENT": return .refinement
        default: return .initiation
        }
    }

    static func sessionStatus(_ s: String) -> SessionStatus {
        switch s { case "COMPLETED": return .completed; case "CANCELLED": return .cancelled; default: return .open }
    }

    static func blockType(_ s: String) -> BlockType {
        switch s {
        case "PADDLE_TIME_PIECES": return .paddleTimePieces
        case "PADDLE_PYRAMID": return .paddlePyramid
        case "RUN_DISTANCE": return .runDistance
        case "RUN_INTERVALS": return .runIntervals
        case "WEIGHTS": return .weights
        case "CIRCUIT": return .circuit
        case "CORE": return .core
        case "TECHNIQUE": return .technique
        default: return .paddleDistance
        }
    }

    static func trainingZone(_ s: String?) -> TrainingZone? {
        switch s {
        case "GA_1": return .ga1
        case "GA_2": return .ga2
        case "E_1": return .e1
        case "E_2": return .e2
        case "AN_MIX": return .anMix
        case "ALACTIC": return .alactic
        case "RECOVERY": return .recovery
        default: return nil
        }
    }

    static func attendanceStatus(_ s: String) -> AttendanceStatus {
        switch s { case "ABSENT": return .absent; case "EXCUSED": return .excused; default: return .present }
    }

    static func repStatus(_ s: String) -> RepEntryStatus {
        switch s { case "COMPLETE": return .complete; case "DNS": return .dns; case "DNF": return .dnf; default: return .pending }
    }
}

/// Parses the backend's zoneless `LocalDate` / `LocalDateTime` strings (interpreted in the current
/// time zone — calendar-day semantics).
enum SyncDate {
    private static func formatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = format
        return f
    }
    /// Date-only values are calendar days — format/parse in the local zone so "2026-06-10" stays the
    /// 10th regardless of where the device is.
    fileprivate static let dateOnly = formatter("yyyy-MM-dd", timeZone: .current)
    /// Session start/end ride as a zoneless `LocalDateTime`. Pin both the format and the parse to UTC
    /// so the absolute `Date` round-trips identically across devices — with `.current` on both ends a
    /// 07:30 EDT session would re-materialize as 07:30 PDT (a different instant) for a cross-zone coach.
    fileprivate static let dateTime = formatter("yyyy-MM-dd'T'HH:mm:ss", timeZone: TimeZone(identifier: "UTC")!)

    static func localDate(_ s: String) -> Date { dateOnly.date(from: s) ?? .distantPast }
    static func localDateTime(_ s: String?) -> Date? { s.flatMap { dateTime.date(from: $0) } }
}

enum SyncMapping {

    /// LWW decision: should the pull leave the local record untouched? True when an un-pushed local
    /// change exists (id in `pending`), or the local copy is at least as new as the server's. A nil
    /// `localUpdatedAt` means no local record — create it, unless `pending` marks a local delete.
    static func skipMerge(id: UUID, server: Date, local: Date?, pending: Set<UUID>) -> Bool {
        if pending.contains(id) { return true }
        if let local { return server <= local }
        return false
    }

    // MARK: - Top-level resources (id-matched)

    static func upsertCoach(_ dto: CoachDTO, in ctx: ModelContext, pending: Set<UUID> = []) {
        let existing = existingCoach(dto.id, in: ctx)
        let server = dto.updatedAt ?? dto.createdAt
        if skipMerge(id: dto.id, server: server, local: existing?.updatedAt, pending: pending) { return }
        let coach = existing ?? insert(Coach(name: dto.name), id: dto.id, in: ctx)
        coach.name = dto.name
        coach.role = dto.role
        coach.nccpLevel = dto.nccpLevel
        coach.colorHex = dto.colorHex
        coach.createdAt = dto.createdAt
        coach.updatedAt = server
    }

    static func upsertAthlete(_ dto: AthleteDTO, in ctx: ModelContext, pending: Set<UUID> = []) {
        let existing = existingAthlete(dto.id, in: ctx)
        if skipMerge(id: dto.id, server: dto.updatedAt, local: existing?.updatedAt, pending: pending) { return }
        let athlete = existing ?? insert(
            Athlete(firstName: dto.firstName, lastName: dto.lastName,
                    dateOfBirth: SyncDate.localDate(dto.dateOfBirth)), id: dto.id, in: ctx)
        athlete.firstName = dto.firstName
        athlete.lastName = dto.lastName
        athlete.dateOfBirth = SyncDate.localDate(dto.dateOfBirth)
        athlete.gender = SyncEnum.gender(dto.gender)
        athlete.guardianName = dto.guardianName
        athlete.guardianPhone = dto.guardianPhone
        athlete.guardianEmail = dto.guardianEmail
        athlete.isActive = dto.active
        athlete.developmentStage = SyncEnum.stage(dto.developmentStage)
        athlete.createdAt = dto.createdAt
        athlete.updatedAt = dto.updatedAt
    }

    static func upsertTeam(_ dto: TeamDTO, in ctx: ModelContext, pending: Set<UUID> = []) {
        let existing = existingTeam(dto.id, in: ctx)
        if skipMerge(id: dto.id, server: dto.updatedAt, local: existing?.updatedAt, pending: pending) { return }
        let team = existing ?? insert(Team(teamName: dto.teamName), id: dto.id, in: ctx)
        team.teamName = dto.teamName
        team.teamDescription = dto.teamDescription
        team.isArchived = dto.archived
        team.createdAt = dto.createdAt
        team.updatedAt = dto.updatedAt
    }

    static func upsertMembership(_ dto: TeamMembershipDTO, in ctx: ModelContext, pending: Set<UUID> = []) {
        let existing = existingMembership(dto.id, in: ctx)
        if skipMerge(id: dto.id, server: dto.updatedAt, local: existing?.updatedAt, pending: pending) { return }
        guard let athlete = existingAthlete(dto.athleteId, in: ctx),
              let team = existingTeam(dto.teamId, in: ctx) else { return }
        let membership = existing ?? insert(TeamMembership(athlete: athlete, team: team), id: dto.id, in: ctx)
        membership.athlete = athlete
        membership.team = team
        membership.joinedDate = SyncDate.localDate(dto.joinedDate)
        membership.leftDate = dto.leftDate.map { SyncDate.localDate($0) }
        membership.updatedAt = dto.updatedAt
    }

    static func upsertSession(_ dto: SessionDTO, in ctx: ModelContext, pending: Set<UUID> = []) {
        let existing = existingSession(dto.id, in: ctx)
        if skipMerge(id: dto.id, server: dto.updatedAt, local: existing?.updatedAt, pending: pending) { return }
        let session = existing ?? insert(
            CoachSession(sessionName: dto.sessionName,
                         scheduledDate: SyncDate.localDate(dto.scheduledDate)), id: dto.id, in: ctx)
        session.sessionName = dto.sessionName
        session.scheduledDate = SyncDate.localDate(dto.scheduledDate)
        session.startTime = SyncDate.localDateTime(dto.startTime)
        session.endTime = SyncDate.localDateTime(dto.endTime)
        session.status = SyncEnum.sessionStatus(dto.status)
        session.weatherNote = dto.weatherNote
        session.teamNote = dto.teamNote
        session.sessionNote = dto.sessionNote
        session.mfCue = dto.mfCue
        session.isArchived = dto.archived
        session.team = dto.teamId.flatMap { existingTeam($0, in: ctx) }
        // Only overwrite the attribution snapshot when the coach resolves — a coach pending local
        // deletion resolves to nil, and nil-ing the stored name would lose attribution; it self-heals
        // on a later pull once the coach exists.
        if let name = dto.coachId.flatMap({ existingCoach($0, in: ctx)?.name }) {
            session.createdByCoachName = name
        }
        session.createdAt = dto.createdAt
        session.updatedAt = dto.updatedAt
    }

    /// Blocks require their parent session to be loaded first; an orphan block is skipped.
    static func upsertBlock(_ dto: BlockDTO, in ctx: ModelContext, pending: Set<UUID> = []) {
        guard let session = existingSession(dto.sessionId, in: ctx) else { return }
        let existing = existingBlock(dto.id, in: ctx)
        if skipMerge(id: dto.id, server: dto.updatedAt, local: existing?.updatedAt, pending: pending) { return }
        let block = existing ?? insert(
            SessionBlock(blockName: dto.blockName, blockType: SyncEnum.blockType(dto.blockType),
                         sortOrder: dto.sortOrder, session: session), id: dto.id, in: ctx)
        block.blockName = dto.blockName
        block.blockType = SyncEnum.blockType(dto.blockType)
        block.sortOrder = dto.sortOrder
        block.repetitionCount = dto.repetitionCount
        block.setCount = dto.setCount
        block.targetDistanceMetres = dto.targetDistanceMetres
        block.distanceKm = dto.distanceKm
        block.restIntervalSeconds = dto.restIntervalSeconds
        block.durationSeconds = dto.durationSeconds
        block.requiresTimeEntry = dto.requiresTimeEntry
        block.trainingZone = SyncEnum.trainingZone(dto.trainingZone)
        block.drillName = dto.drillName
        block.coachNote = dto.coachNote
        block.prescribedRepDurationsSec = dto.prescribedRepDurationsSec
        block.session = session
        block.updatedAt = dto.updatedAt
    }

    static func upsertNote(_ dto: NoteDTO, in ctx: ModelContext, pending: Set<UUID> = []) {
        let existing = existingNote(dto.id, in: ctx)
        if skipMerge(id: dto.id, server: dto.updatedAt, local: existing?.updatedAt, pending: pending) { return }
        guard let athlete = existingAthlete(dto.athleteId, in: ctx),
              let session = existingSession(dto.sessionId, in: ctx) else { return }
        let note = existing ?? insert(
            AthleteNote(noteText: dto.noteText, athlete: athlete, session: session), id: dto.id, in: ctx)
        note.noteText = dto.noteText
        note.athlete = athlete
        note.session = session
        note.sessionBlock = dto.sessionBlockId.flatMap { existingBlock($0, in: ctx) }
        // Preserve the attribution snapshot when the coach can't be resolved (e.g. pending local
        // delete) rather than nil-ing it; self-heals on a later pull.
        if let name = dto.coachId.flatMap({ existingCoach($0, in: ctx)?.name }) {
            note.createdByCoachName = name
        }
        note.createdAt = dto.createdAt
        note.updatedAt = dto.updatedAt
    }

    // MARK: - Leaf records (natural-key merge — ids diverge between app and backend)

    static func upsertAttendance(_ dto: AttendanceDTO, session: CoachSession,
                                 in ctx: ModelContext, pending: Set<UUID> = []) {
        let existing = (session.attendanceRecords ?? []).first { $0.athlete?.id == dto.athleteId }
        if let existing, skipMerge(id: existing.id, server: dto.updatedAt, local: existing.updatedAt, pending: pending) {
            return
        }
        guard let athlete = existingAthlete(dto.athleteId, in: ctx) else { return }
        let record = existing ?? insert(AttendanceRecord(athlete: athlete, session: session), in: ctx)
        record.athlete = athlete
        record.session = session
        record.status = SyncEnum.attendanceStatus(dto.status)
        record.absenceReason = dto.absenceReason
        record.updatedAt = dto.updatedAt
    }

    static func upsertPerformance(_ dto: PerformanceDTO, block: SessionBlock,
                                  in ctx: ModelContext, pending: Set<UUID> = []) {
        let existing = (block.performanceRecords ?? [])
            .first { $0.athlete?.id == dto.athleteId && $0.repNumber == dto.repNumber }
        if let existing, skipMerge(id: existing.id, server: dto.updatedAt, local: existing.updatedAt, pending: pending) {
            return
        }
        guard let athlete = existingAthlete(dto.athleteId, in: ctx) else { return }
        let slot = existing ?? insert(
            PerformanceRecord(athlete: athlete, sessionBlock: block, repNumber: dto.repNumber), in: ctx)
        slot.athlete = athlete
        slot.sessionBlock = block
        slot.repNumber = dto.repNumber
        slot.recordedTimeMs = dto.recordedTimeMs
        slot.status = SyncEnum.repStatus(dto.status)
        slot.updatedAt = dto.updatedAt
    }

    // MARK: - Athlete-scoped domains (id-matched)

    static func upsertAssessment(_ dto: AssessmentDTO, in ctx: ModelContext, pending: Set<UUID> = []) {
        let existing = existingAssessment(dto.id, in: ctx)
        if skipMerge(id: dto.id, server: dto.updatedAt, local: existing?.updatedAt, pending: pending) { return }
        guard let athlete = existingAthlete(dto.athleteId, in: ctx) else { return }
        let assessment = existing ?? insert(
            TechnicalAssessment(date: SyncDate.localDate(dto.date), stage: SyncEnum.stage(dto.stage),
                                athlete: athlete), id: dto.id, in: ctx)
        assessment.athlete = athlete
        assessment.date = SyncDate.localDate(dto.date)
        assessment.stage = SyncEnum.stage(dto.stage)
        assessment.overallNotes = dto.overallNotes
        assessment.createdAt = dto.createdAt
        assessment.updatedAt = dto.updatedAt
        // Ratings are a replace-all sub-aggregate.
        (assessment.ratings ?? []).forEach { ctx.delete($0) }
        for r in dto.ratings {
            ctx.insert(TechnicalRating(category: r.category, factor: r.factor, score: r.score,
                                       comment: r.comment, assessment: assessment))
        }
    }

    static func upsertFitnessTest(_ dto: FitnessTestDTO, in ctx: ModelContext, pending: Set<UUID> = []) {
        let existing = existingFitnessTest(dto.id, in: ctx)
        if skipMerge(id: dto.id, server: dto.updatedAt, local: existing?.updatedAt, pending: pending) { return }
        guard let athlete = existingAthlete(dto.athleteId, in: ctx) else { return }
        let test = existing ?? insert(
            FitnessTestResult(testType: dto.testType, result: dto.result, unit: dto.unit,
                              testDate: SyncDate.localDate(dto.testDate), athlete: athlete), id: dto.id, in: ctx)
        test.athlete = athlete
        test.testType = dto.testType
        test.result = dto.result
        test.unit = dto.unit
        test.testDate = SyncDate.localDate(dto.testDate)
        test.notes = dto.notes
        test.createdAt = dto.createdAt
        test.updatedAt = dto.updatedAt
    }

    static func upsertRegatta(_ dto: RegattaResultDTO, in ctx: ModelContext, pending: Set<UUID> = []) {
        let existing = existingRegatta(dto.id, in: ctx)
        if skipMerge(id: dto.id, server: dto.updatedAt, local: existing?.updatedAt, pending: pending) { return }
        guard let athlete = existingAthlete(dto.athleteId, in: ctx) else { return }
        let result = existing ?? insert(
            RegattaResult(regattaName: dto.regattaName, regattaDate: SyncDate.localDate(dto.regattaDate),
                          eventDistance: dto.eventDistanceMetres, resultTimeMs: dto.resultTimeMs,
                          athlete: athlete), id: dto.id, in: ctx)
        result.athlete = athlete
        result.regattaName = dto.regattaName
        result.location = dto.location
        result.regattaDate = SyncDate.localDate(dto.regattaDate)
        result.eventDistance = dto.eventDistanceMetres
        result.placement = dto.placement
        result.totalCompetitors = dto.totalCompetitors
        result.resultTimeMs = dto.resultTimeMs
        result.notes = dto.notes
        result.createdAt = dto.createdAt
        result.updatedAt = dto.updatedAt
    }

    static func upsertJournal(_ dto: JournalDTO, in ctx: ModelContext, pending: Set<UUID> = []) {
        let existing = existingJournal(dto.id, in: ctx)
        if skipMerge(id: dto.id, server: dto.updatedAt, local: existing?.updatedAt, pending: pending) { return }
        guard let athlete = existingAthlete(dto.athleteId, in: ctx) else { return }
        let note = existing ?? insert(
            DevelopmentNote(date: SyncDate.localDate(dto.date), text: dto.text, tags: dto.tags,
                            athlete: athlete), id: dto.id, in: ctx)
        note.athlete = athlete
        note.date = SyncDate.localDate(dto.date)
        note.text = dto.text
        note.tags = dto.tags
        // Preserve the attribution snapshot when the coach can't be resolved (e.g. pending local
        // delete) rather than nil-ing it; self-heals on a later pull.
        if let name = dto.coachId.flatMap({ existingCoach($0, in: ctx)?.name }) {
            note.createdByCoachName = name
        }
        note.createdAt = dto.createdAt
        note.updatedAt = dto.updatedAt
    }

    static func upsertKtc(_ dto: KtcDTO, in ctx: ModelContext, pending: Set<UUID> = []) {
        let existing = existingKtc(dto.id, in: ctx)
        if skipMerge(id: dto.id, server: dto.updatedAt, local: existing?.updatedAt, pending: pending) { return }
        guard let athlete = existingAthlete(dto.athleteId, in: ctx) else { return }
        let ktc = existing ?? insert(
            KTCAssessment(date: SyncDate.localDate(dto.date), window: dto.window,
                          setupRecoveryScore: dto.setupRecoveryScore, catchScore: dto.catchScore,
                          propulsionDrawScore: dto.propulsionDrawScore, exitScore: dto.exitScore,
                          athlete: athlete), id: dto.id, in: ctx)
        ktc.athlete = athlete
        ktc.date = SyncDate.localDate(dto.date)
        ktc.window = dto.window
        ktc.setupRecoveryScore = dto.setupRecoveryScore
        ktc.catchScore = dto.catchScore
        ktc.propulsionDrawScore = dto.propulsionDrawScore
        ktc.exitScore = dto.exitScore
        ktc.notes = dto.notes
        ktc.createdAt = dto.createdAt
        ktc.updatedAt = dto.updatedAt
    }

    static func upsertHeight(_ dto: HeightRecordDTO, in ctx: ModelContext, pending: Set<UUID> = []) {
        let existing = existingHeight(dto.id, in: ctx)
        if skipMerge(id: dto.id, server: dto.updatedAt, local: existing?.updatedAt, pending: pending) { return }
        guard let athlete = existingAthlete(dto.athleteId, in: ctx) else { return }
        let height = existing ?? insert(
            HeightRecord(heightCm: dto.heightCm, date: SyncDate.localDate(dto.date), athlete: athlete),
            id: dto.id, in: ctx)
        height.athlete = athlete
        height.heightCm = dto.heightCm
        height.date = SyncDate.localDate(dto.date)
        height.createdAt = dto.createdAt
        height.updatedAt = dto.updatedAt
    }

    // MARK: - Insert helpers

    /// Inserts a freshly-built model, assigning the backend id (id-matched resources).
    private static func insert<T: PersistentModel & SyncedModel>(_ model: T, id: UUID, in ctx: ModelContext) -> T {
        model.id = id
        ctx.insert(model)
        return model
    }

    /// Inserts a freshly-built leaf model (natural-key — keeps its own generated id).
    private static func insert<T: PersistentModel>(_ model: T, in ctx: ModelContext) -> T {
        ctx.insert(model)
        return model
    }

    // MARK: - existing-by-id lookups

    private static func existingCoach(_ id: UUID, in ctx: ModelContext) -> Coach? {
        var d = FetchDescriptor<Coach>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? ctx.fetch(d).first
    }
    private static func existingAthlete(_ id: UUID, in ctx: ModelContext) -> Athlete? {
        var d = FetchDescriptor<Athlete>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? ctx.fetch(d).first
    }
    private static func existingTeam(_ id: UUID, in ctx: ModelContext) -> Team? {
        var d = FetchDescriptor<Team>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? ctx.fetch(d).first
    }
    private static func existingMembership(_ id: UUID, in ctx: ModelContext) -> TeamMembership? {
        var d = FetchDescriptor<TeamMembership>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? ctx.fetch(d).first
    }
    private static func existingSession(_ id: UUID, in ctx: ModelContext) -> CoachSession? {
        var d = FetchDescriptor<CoachSession>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? ctx.fetch(d).first
    }
    private static func existingBlock(_ id: UUID, in ctx: ModelContext) -> SessionBlock? {
        var d = FetchDescriptor<SessionBlock>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? ctx.fetch(d).first
    }
    private static func existingNote(_ id: UUID, in ctx: ModelContext) -> AthleteNote? {
        var d = FetchDescriptor<AthleteNote>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? ctx.fetch(d).first
    }
    private static func existingAssessment(_ id: UUID, in ctx: ModelContext) -> TechnicalAssessment? {
        var d = FetchDescriptor<TechnicalAssessment>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? ctx.fetch(d).first
    }
    private static func existingFitnessTest(_ id: UUID, in ctx: ModelContext) -> FitnessTestResult? {
        var d = FetchDescriptor<FitnessTestResult>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? ctx.fetch(d).first
    }
    private static func existingRegatta(_ id: UUID, in ctx: ModelContext) -> RegattaResult? {
        var d = FetchDescriptor<RegattaResult>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? ctx.fetch(d).first
    }
    private static func existingJournal(_ id: UUID, in ctx: ModelContext) -> DevelopmentNote? {
        var d = FetchDescriptor<DevelopmentNote>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? ctx.fetch(d).first
    }
    private static func existingKtc(_ id: UUID, in ctx: ModelContext) -> KTCAssessment? {
        var d = FetchDescriptor<KTCAssessment>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? ctx.fetch(d).first
    }
    private static func existingHeight(_ id: UUID, in ctx: ModelContext) -> HeightRecord? {
        var d = FetchDescriptor<HeightRecord>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? ctx.fetch(d).first
    }
}

// MARK: - Reverse translation (app → backend) for the write/push path

extension SyncEnum {
    static func name(_ g: Gender?) -> String? {
        switch g { case .male: return "MALE"; case .female: return "FEMALE"; case nil: return nil }
    }
    static func name(_ s: DevelopmentStage) -> String {
        switch s {
        case .initiation:    return "INITIATION"
        case .acquisition:   return "ACQUISITION"
        case .consolidation: return "CONSOLIDATION"
        case .refinement:    return "REFINEMENT"
        }
    }
    static func name(_ s: SessionStatus) -> String {
        switch s { case .open: return "OPEN"; case .completed: return "COMPLETED"; case .cancelled: return "CANCELLED" }
    }
    static func name(_ b: BlockType) -> String {
        switch b {
        case .paddleDistance:   return "PADDLE_DISTANCE"
        case .paddleTimePieces: return "PADDLE_TIME_PIECES"
        case .paddlePyramid:    return "PADDLE_PYRAMID"
        case .runDistance:      return "RUN_DISTANCE"
        case .runIntervals:     return "RUN_INTERVALS"
        case .weights:          return "WEIGHTS"
        case .circuit:          return "CIRCUIT"
        case .core:             return "CORE"
        case .technique:        return "TECHNIQUE"
        }
    }
    static func name(_ z: TrainingZone?) -> String? {
        switch z {
        case .ga1:      return "GA_1"
        case .ga2:      return "GA_2"
        case .e1:       return "E_1"
        case .e2:       return "E_2"
        case .anMix:    return "AN_MIX"
        case .alactic:  return "ALACTIC"
        case .recovery: return "RECOVERY"
        case nil:       return nil
        }
    }
    static func name(_ a: AttendanceStatus) -> String {
        switch a { case .present: return "PRESENT"; case .absent: return "ABSENT"; case .excused: return "EXCUSED" }
    }
    static func name(_ r: RepEntryStatus) -> String {
        switch r { case .pending: return "PENDING"; case .complete: return "COMPLETE"; case .dns: return "DNS"; case .dnf: return "DNF" }
    }
}

extension SyncDate {
    /// `Date` → backend "yyyy-MM-dd" (calendar day, current time zone — symmetric with the parse).
    static func localDateString(_ d: Date) -> String { dateOnly.string(from: d) }
    /// `Date?` → backend zoneless "yyyy-MM-dd'T'HH:mm:ss".
    static func localDateTimeString(_ d: Date?) -> String? { d.map { dateTime.string(from: $0) } }
    /// `Date` → ISO-8601 UTC with milliseconds (the backend's `Instant`, drives LWW ordering).
    static func instantString(_ d: Date) -> String { iso.string(from: d) }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
