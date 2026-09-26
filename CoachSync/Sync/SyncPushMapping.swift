/// Reverse mappers (Stage 3b push): a synced `@Model` → its backend request DTO. The inverse of
/// the forward upserts in `SyncMapping`. Enum/date translation goes through `SyncEnum.name` and the
/// reverse `SyncDate` helpers. Bodies carry the app's own `id` (id-matched sync) and the model's
/// `updatedAt` (last-write-wins). Parent ids that live in the URL (a block's session, a note's
/// session) are read by the pusher, not here; ids the body itself needs (a note's athlete/block,
/// a membership's athlete) are read from the model's relationships.

import Foundation

enum SyncPush {

    static func athleteRequest(_ a: Athlete) -> AthleteRequestDTO {
        AthleteRequestDTO(
            id: a.id, firstName: a.firstName, lastName: a.lastName,
            dateOfBirth: SyncDate.localDateString(a.dateOfBirth),
            gender: SyncEnum.name(a.gender),
            guardianName: a.guardianName, guardianPhone: a.guardianPhone, guardianEmail: a.guardianEmail,
            developmentStage: SyncEnum.name(a.developmentStage),
            active: a.isActive,
            updatedAt: SyncDate.instantString(a.updatedAt))
    }

    static func teamRequest(_ t: Team) -> TeamRequestDTO {
        TeamRequestDTO(id: t.id, teamName: t.teamName, teamDescription: t.teamDescription,
                       archived: t.isArchived, updatedAt: SyncDate.instantString(t.updatedAt))
    }

    static func membershipRequest(_ m: TeamMembership) -> TeamMembershipRequestDTO {
        TeamMembershipRequestDTO(
            id: m.id, athleteId: m.athlete?.id ?? UUID(),
            joinedDate: SyncDate.localDateString(m.joinedDate),
            leftDate: m.leftDate.map { SyncDate.localDateString($0) },
            updatedAt: SyncDate.instantString(m.updatedAt))
    }

    static func sessionRequest(_ s: CoachSession) -> SessionRequestDTO {
        SessionRequestDTO(
            id: s.id, sessionName: s.sessionName,
            scheduledDate: SyncDate.localDateString(s.scheduledDate),
            startTime: SyncDate.localDateTimeString(s.startTime),
            endTime: SyncDate.localDateTimeString(s.endTime),
            weatherNote: s.weatherNote, teamNote: s.teamNote, sessionNote: s.sessionNote, mfCue: s.mfCue,
            teamId: s.team?.id,
            status: SyncEnum.name(s.status), archived: s.isArchived,
            updatedAt: SyncDate.instantString(s.updatedAt))
    }

    static func blockRequest(_ b: SessionBlock) -> BlockRequestDTO {
        BlockRequestDTO(
            id: b.id, blockName: b.blockName, blockType: SyncEnum.name(b.blockType),
            sortOrder: b.sortOrder, repetitionCount: b.repetitionCount, setCount: b.setCount,
            targetDistanceMetres: b.targetDistanceMetres, distanceKm: b.distanceKm,
            restIntervalSeconds: b.restIntervalSeconds, durationSeconds: b.durationSeconds,
            requiresTimeEntry: b.requiresTimeEntry, trainingZone: SyncEnum.name(b.trainingZone),
            drillName: b.drillName, coachNote: b.coachNote,
            prescribedRepDurationsSec: b.prescribedRepDurationsSec,
            updatedAt: SyncDate.instantString(b.updatedAt))
    }

    static func noteCreateRequest(_ n: AthleteNote) -> NoteCreateRequestDTO {
        NoteCreateRequestDTO(
            id: n.id, athleteId: n.athlete?.id ?? UUID(), noteText: n.noteText,
            sessionBlockId: n.sessionBlock?.id, updatedAt: SyncDate.instantString(n.updatedAt))
    }

    static func noteUpdateRequest(_ n: AthleteNote) -> NoteUpdateRequestDTO {
        NoteUpdateRequestDTO(noteText: n.noteText, sessionBlockId: n.sessionBlock?.id,
                             updatedAt: SyncDate.instantString(n.updatedAt))
    }

    static func assessmentRequest(_ a: TechnicalAssessment) -> AssessmentRequestDTO {
        let ratings = (a.ratings ?? []).map {
            RatingRequestDTO(category: $0.category, factor: $0.factor, score: $0.score, comment: $0.comment)
        }
        return AssessmentRequestDTO(
            id: a.id, date: SyncDate.localDateString(a.date), stage: SyncEnum.name(a.stage),
            overallNotes: a.overallNotes, ratings: ratings, updatedAt: SyncDate.instantString(a.updatedAt))
    }

    static func fitnessTestRequest(_ f: FitnessTestResult) -> FitnessTestRequestDTO {
        FitnessTestRequestDTO(
            id: f.id, testType: f.testType, result: f.result, unit: f.unit,
            testDate: SyncDate.localDateString(f.testDate), notes: f.notes,
            updatedAt: SyncDate.instantString(f.updatedAt))
    }

    static func regattaRequest(_ r: RegattaResult) -> RegattaResultRequestDTO {
        RegattaResultRequestDTO(
            id: r.id, regattaName: r.regattaName, location: r.location,
            regattaDate: SyncDate.localDateString(r.regattaDate), eventDistanceMetres: r.eventDistance,
            placement: r.placement, totalCompetitors: r.totalCompetitors, resultTimeMs: r.resultTimeMs,
            notes: r.notes, updatedAt: SyncDate.instantString(r.updatedAt))
    }

    static func journalRequest(_ n: DevelopmentNote) -> JournalRequestDTO {
        JournalRequestDTO(
            id: n.id, date: SyncDate.localDateString(n.date), text: n.text, tags: n.tags,
            updatedAt: SyncDate.instantString(n.updatedAt))
    }

    static func ktcRequest(_ k: KTCAssessment) -> KtcRequestDTO {
        KtcRequestDTO(
            id: k.id, date: SyncDate.localDateString(k.date), window: k.window,
            setupRecoveryScore: k.setupRecoveryScore, catchScore: k.catchScore,
            propulsionDrawScore: k.propulsionDrawScore, exitScore: k.exitScore,
            notes: k.notes, updatedAt: SyncDate.instantString(k.updatedAt))
    }

    static func heightRequest(_ h: HeightRecord) -> HeightRecordRequestDTO {
        HeightRecordRequestDTO(id: h.id, heightCm: h.heightCm,
                               date: SyncDate.localDateString(h.date),
                               updatedAt: SyncDate.instantString(h.updatedAt))
    }

    static func coachRequest(_ c: Coach) -> CoachRequestDTO {
        CoachRequestDTO(id: c.id, name: c.name, role: c.role, nccpLevel: c.nccpLevel,
                        colorHex: c.colorHex, updatedAt: SyncDate.instantString(c.updatedAt))
    }

    /// One attendance record → a single-entry bulk upsert (the app pushes per record).
    static func attendanceRequest(_ r: AttendanceRecord) -> AttendanceUpdateRequestDTO {
        AttendanceUpdateRequestDTO(entries: [
            AttendanceEntryDTO(id: r.id, athleteId: r.athlete?.id ?? UUID(),
                               status: SyncEnum.name(r.status), absenceReason: r.absenceReason,
                               updatedAt: SyncDate.instantString(r.updatedAt))
        ])
    }

    /// One rep slot → a single-entry natural-key upsert (matched by athlete + rep, not id).
    static func performanceRequest(_ p: PerformanceRecord) -> PerformanceUpsertRequestDTO {
        PerformanceUpsertRequestDTO(entries: [
            PerformanceUpsertEntryDTO(athleteId: p.athlete?.id ?? UUID(), repNumber: p.repNumber,
                                      status: SyncEnum.name(p.status), recordedTimeMs: p.recordedTimeMs,
                                      updatedAt: SyncDate.instantString(p.updatedAt))
        ])
    }
}
