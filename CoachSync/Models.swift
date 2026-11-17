/// Defines the SwiftData models and shared domain enums used by CoachSync.

import Foundation
import SwiftData
import SwiftUI

// MARK: - Athlete

/// Stores athlete profile data and owns the athlete's historical relationships.
///
/// CloudKit compatibility: every non-optional stored property has a
/// declaration-level default so SwiftData can satisfy the CloudKit schema.
/// All relationship delete rules are `.nullify` (CloudKit forbids cascade);
/// hand-rolled cleanup lives in `ModelContext.deleteAthleteCascade`.
@Model
class Athlete {
    var id: UUID = UUID()
    /// Last local edit time; the basis for last-write-wins backend sync (Phase 2).
    /// Stamped at the SwiftData save chokepoint when this record is created or changed.
    var updatedAt: Date = Date()
    var firstName: String = ""
    var lastName: String = ""
    var dateOfBirth: Date = Date.distantPast
    var gender: Gender?
    var guardianName: String?
    var guardianPhone: String?
    var guardianEmail: String?
    var isActive: Bool = true
    var createdAt: Date = Date()
    var developmentStage: DevelopmentStage = DevelopmentStage.initiation

    @Relationship(deleteRule: .nullify, inverse: \TeamMembership.athlete)
    var memberships: [TeamMembership]?
    @Relationship(deleteRule: .nullify, inverse: \AttendanceRecord.athlete)
    var attendanceRecords: [AttendanceRecord]?
    @Relationship(deleteRule: .nullify, inverse: \PerformanceRecord.athlete)
    var performanceRecords: [PerformanceRecord]?
    @Relationship(deleteRule: .nullify, inverse: \AthleteNote.athlete)
    var notes: [AthleteNote]?
    @Relationship(deleteRule: .nullify, inverse: \FitnessTestResult.athlete)
    var fitnessTestResults: [FitnessTestResult]?
    @Relationship(deleteRule: .nullify, inverse: \RegattaResult.athlete)
    var regattaResults: [RegattaResult]?
    @Relationship(deleteRule: .nullify, inverse: \TechnicalAssessment.athlete)
    var technicalAssessments: [TechnicalAssessment]?
    @Relationship(deleteRule: .nullify, inverse: \HeightRecord.athlete)
    var heightRecords: [HeightRecord]?
    @Relationship(deleteRule: .nullify, inverse: \DevelopmentNote.athlete)
    var developmentNotes: [DevelopmentNote]?
    @Relationship(deleteRule: .nullify, inverse: \KTCAssessment.athlete)
    var ktcAssessments: [KTCAssessment]?

    /// Creates a new active athlete with empty related collections.
    init(firstName: String, lastName: String, dateOfBirth: Date,
         gender: Gender? = nil, guardianName: String? = nil,
         guardianPhone: String? = nil, guardianEmail: String? = nil) {
        self.id = UUID()
        self.firstName = firstName
        self.lastName = lastName
        self.dateOfBirth = dateOfBirth
        self.gender = gender
        self.guardianName = guardianName
        self.guardianPhone = guardianPhone
        self.guardianEmail = guardianEmail
        self.isActive = true
        self.createdAt = Date()
        self.developmentStage = .initiation
        self.memberships = []
        self.attendanceRecords = []
        self.performanceRecords = []
        self.notes = []
        self.fitnessTestResults = []
        self.regattaResults = []
        self.technicalAssessments = []
        self.heightRecords = []
        self.developmentNotes = []
        self.ktcAssessments = []
    }

    /// Computed at read time so the category updates automatically as seasons change.
    var ageCategory: String {
        SeasonContext.ageCategory(for: dateOfBirth)
    }

    /// Convenience display name used throughout the UI.
    var fullName: String { "\(firstName) \(lastName)" }

    /// True if the athlete has any recorded history that must be preserved.
    /// Such an athlete may be deactivated but not deleted; one with no history
    /// (a bare team membership aside) may be deleted outright.
    ///
    /// "History" means data the coach actually recorded. Roster-tracking
    /// artifacts do NOT count: attendance records where the athlete was never
    /// present (a kid rostered once and marked absent), and pre-generated rep
    /// slots that were never filled (`.pending` with no time). Without these
    /// carve-outs an athlete who never attended a single practice becomes
    /// permanently undeletable. DNS/DNF marks DO count — they are deliberate
    /// race-piece outcomes.
    var hasPracticeHistory: Bool {
        (attendanceRecords ?? []).contains { $0.status == .present } ||
        (performanceRecords ?? []).contains { $0.holdsRecordedData } ||
        notes?.isEmpty == false ||
        fitnessTestResults?.isEmpty == false ||
        regattaResults?.isEmpty == false ||
        technicalAssessments?.isEmpty == false ||
        heightRecords?.isEmpty == false ||
        developmentNotes?.isEmpty == false ||
        ktcAssessments?.isEmpty == false
    }
}

// MARK: - Team

/// Groups athletes for training and scheduling.
///
/// CloudKit compatibility: see notes on `Athlete`. Hand-rolled cleanup for
/// the membership join records lives in `ModelContext.deleteTeamCascade`.
@Model
class Team {
    var id: UUID = UUID()
    /// Last local edit time; the basis for last-write-wins backend sync (Phase 2).
    /// Stamped at the SwiftData save chokepoint when this record is created or changed.
    var updatedAt: Date = Date()
    var teamName: String = ""
    var teamDescription: String?
    var isArchived: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \TeamMembership.team)
    var memberships: [TeamMembership]?
    /// Sessions are intentionally retained when a team is deleted so historical
    /// data isn't lost — they keep their `team` reference nilled out.
    @Relationship(deleteRule: .nullify, inverse: \CoachSession.team)
    var sessions: [CoachSession]?

    init(teamName: String, description: String? = nil) {
        self.id = UUID()
        self.teamName = teamName
        self.teamDescription = description
        self.isArchived = false
        self.createdAt = Date()
        self.memberships = []
        self.sessions = []
    }

    /// Returns only memberships that have not been ended.
    var activeMembers: [Athlete] {
        (memberships ?? [])
            .filter { $0.leftDate == nil }
            .compactMap { $0.athlete }
            .filter { $0.isActive }
    }
}

// MARK: - TeamMembership

/// Represents an athlete's participation in a team over a date range.
@Model
class TeamMembership {
    var id: UUID = UUID()
    /// Last local edit time; the basis for last-write-wins backend sync (Phase 2).
    /// Stamped at the SwiftData save chokepoint when this record is created or changed.
    var updatedAt: Date = Date()
    var joinedDate: Date = Date()
    var leftDate: Date?

    var athlete: Athlete?
    var team: Team?

    /// Creates an active membership starting today.
    init(athlete: Athlete, team: Team) {
        self.id = UUID()
        self.joinedDate = Date()
        self.leftDate = nil
        self.athlete = athlete
        self.team = team
    }
}

// MARK: - CoachSession

/// A scheduled or completed training session.
///
/// CloudKit compatibility: see notes on `Athlete`. Hand-rolled cleanup for
/// child records lives in `ModelContext.deleteSessionCascade`.
@Model
class CoachSession {
    var id: UUID = UUID()
    /// Last local edit time; the basis for last-write-wins backend sync (Phase 2).
    /// Stamped at the SwiftData save chokepoint when this record is created or changed.
    var updatedAt: Date = Date()
    var sessionName: String = ""
    var scheduledDate: Date = Date()
    var startTime: Date?
    var endTime: Date?
    var status: SessionStatus = SessionStatus.open
    var weatherNote: String?
    var teamNote: String?
    var isArchived: Bool = false
    var createdAt: Date = Date()

    /// Name of the coach who created this session, for "logged by" attribution.
    /// Optional → CloudKit-safe; a name snapshot rather than a hard relationship.
    var createdByCoachName: String?

    var mfCue: String?
    var sessionNote: String?
    var team: Team?

    @Relationship(deleteRule: .nullify, inverse: \SessionBlock.session)
    var sessionBlocks: [SessionBlock]?
    @Relationship(deleteRule: .nullify, inverse: \AttendanceRecord.session)
    var attendanceRecords: [AttendanceRecord]?
    @Relationship(deleteRule: .nullify, inverse: \AthleteNote.session)
    var athleteNotes: [AthleteNote]?

    /// Creates a scheduled session with no recorded data.
    init(sessionName: String, scheduledDate: Date, team: Team? = nil) {
        self.id = UUID()
        self.sessionName = sessionName
        self.scheduledDate = scheduledDate
        self.status = .open
        self.isArchived = false
        self.team = team
        self.createdAt = Date()
        self.sessionBlocks = []
        self.attendanceRecords = []
        self.athleteNotes = []
    }

    /// Completed sessions are permanently preserved and cannot be deleted —
    /// coaches archive the season instead. Any other status may be deleted.
    var isDeletable: Bool {
        status != .completed
    }
}

// MARK: - SessionBlock

/// A concrete workout block attached to a specific session.
///
/// CloudKit compatibility: see notes on `Athlete`. Hand-rolled cleanup for
/// performance records lives in `ModelContext.deleteBlockCascade` (which preserves
/// anchored notes — they're owned by the session, not the block).
@Model
class SessionBlock {
    var id: UUID = UUID()
    /// Last local edit time; the basis for last-write-wins backend sync (Phase 2).
    /// Stamped at the SwiftData save chokepoint when this record is created or changed.
    var updatedAt: Date = Date()
    var blockName: String = ""
    var blockType: BlockType = BlockType.paddleDistance
    var sortOrder: Int = 0
    /// Canonical per-rep slot capacity for trackable blocks. For pyramids,
    /// `AddBlockSheet` keeps this equal to pattern-length × setCount at save —
    /// readers never re-derive capacity from the pyramid fields.
    var repetitionCount: Int = 1
    var targetDistanceMetres: Double?
    var coachNote: String?
    var trainingZone: TrainingZone?
    var distanceKm: Double?
    var restIntervalSeconds: Int?

    /// When false, the logger renders per-rep checkboxes instead of time-entry
    /// fields. Used by check-off interval blocks and pyramid blocks.
    var requiresTimeEntry: Bool = true

    /// For pyramid blocks: array of seconds per rep within one set
    /// (e.g. [240, 120, 60, 30, 60, 120, 240] for a 4-2-1-30s-1-2-4 pyramid).
    /// `nil` for non-pyramid blocks.
    var prescribedRepDurationsSec: [Int]? = nil

    /// For pyramid blocks: how many sets of the pattern. 1 for non-pyramid blocks.
    var setCount: Int = 1

    /// Total block duration for blocks without per-rep structure
    /// (warmup, cooldown, technique, circuit, core).
    var durationSeconds: Int? = nil

    /// Drill description for warmup/technique blocks.
    var drillName: String? = nil

    var session: CoachSession?

    @Relationship(deleteRule: .nullify, inverse: \PerformanceRecord.sessionBlock)
    var performanceRecords: [PerformanceRecord]?
    @Relationship(deleteRule: .nullify, inverse: \AthleteNote.sessionBlock)
    var athleteNotes: [AthleteNote]?

    /// Creates a custom block for a session.
    init(blockName: String, blockType: BlockType, sortOrder: Int,
         repetitionCount: Int = 1, session: CoachSession,
         trainingZone: TrainingZone? = nil, distanceKm: Double? = nil) {
        self.id = UUID()
        self.blockName = blockName
        self.blockType = blockType
        self.sortOrder = sortOrder
        self.repetitionCount = repetitionCount
        self.trainingZone = trainingZone
        self.distanceKm = distanceKm
        self.session = session
        self.performanceRecords = []
        self.athleteNotes = []
    }
}

/// Shared distance calculations for session blocks.
extension SessionBlock {
    /// Returns the best available total block distance in kilometers.
    var effectiveDistanceKm: Double? {
        if let km = distanceKm { return km }
        guard let metres = targetDistanceMetres else { return nil }
        return (Double(repetitionCount) * metres) / 1000.0
    }

    /// Highest rep number holding coach-recorded data (a time, DNS, or DNF);
    /// 0 when no slot does. An edit may not shrink the block's rep capacity
    /// below this number — that would strand recorded results where the
    /// logger no longer renders them while analytics still count them.
    var highestFilledRepNumber: Int {
        (performanceRecords ?? [])
            .filter(\.holdsRecordedData)
            .map(\.repNumber)
            .max() ?? 0
    }
}

// MARK: - AttendanceRecord

/// Records an athlete's attendance status for a session.
@Model
class AttendanceRecord {
    var id: UUID = UUID()
    /// Last local edit time; the basis for last-write-wins backend sync (Phase 2).
    /// Stamped at the SwiftData save chokepoint when this record is created or changed.
    var updatedAt: Date = Date()
    var status: AttendanceStatus = AttendanceStatus.present
    var absenceReason: String?

    var session: CoachSession?
    var athlete: Athlete?

    /// Creates an attendance record for one athlete in one session.
    init(athlete: Athlete, session: CoachSession,
         status: AttendanceStatus = .present) {
        self.id = UUID()
        self.status = status
        self.athlete = athlete
        self.session = session
    }
}

// MARK: - PerformanceRecord

/// A pre-generated slot for one athlete × one rep within a block, filled during session execution.
@Model
class PerformanceRecord {
    var id: UUID = UUID()
    /// Last local edit time; the basis for last-write-wins backend sync (Phase 2).
    /// Stamped at the SwiftData save chokepoint when this record is created or changed.
    var updatedAt: Date = Date()
    var repNumber: Int = 1
    var recordedTimeMs: Int?
    var status: RepEntryStatus = RepEntryStatus.pending
    var createdAt: Date = Date()

    var sessionBlock: SessionBlock?
    var athlete: Athlete?

    /// Creates a pending rep slot for one athlete and repetition.
    init(athlete: Athlete, sessionBlock: SessionBlock, repNumber: Int,
         recordedTimeMs: Int? = nil, status: RepEntryStatus = .pending) {
        self.id = UUID()
        self.repNumber = repNumber
        self.recordedTimeMs = recordedTimeMs
        self.status = status
        self.createdAt = Date()
        self.athlete = athlete
        self.sessionBlock = sessionBlock
    }

    /// True when this slot holds data the coach actually recorded — a time,
    /// or a deliberate DNS/DNF outcome. Pre-generated `.pending` slots with no
    /// time are roster artifacts, not history. This is the same carve-out
    /// `Athlete.hasPracticeHistory` applies, and the rule slot reconciliation
    /// uses to decide what may never be silently deleted or hidden.
    var holdsRecordedData: Bool {
        status != .pending || recordedTimeMs != nil
    }

    /// Formats stored timing data for display while preserving DNS and DNF markers.
    var formattedTime: String? {
        guard let ms = recordedTimeMs else {
            // A `.complete` record should always carry a time (the logger only
            // marks complete when one is entered); show a visible sentinel
            // rather than blank if that invariant is ever violated.
            switch status {
            case .dns: return "DNS"
            case .dnf: return "DNF"
            case .complete: return "—"
            case .pending: return nil
            }
        }
        return formatMillisecondsForDisplay(ms)
    }
}

// MARK: - AthleteNote

/// A coach note attached to an athlete within the context of a session or block.
@Model
class AthleteNote {
    var id: UUID = UUID()
    /// Last local edit time; the basis for last-write-wins backend sync (Phase 2).
    /// Stamped at the SwiftData save chokepoint when this record is created or changed.
    var updatedAt: Date = Date()
    var noteText: String = ""
    var createdAt: Date = Date()

    /// Name of the coach who wrote this note, for "logged by" attribution.
    var createdByCoachName: String?

    var session: CoachSession?
    var sessionBlock: SessionBlock?
    var athlete: Athlete?

    /// Creates a note attached to an athlete and session, with an optional block context.
    init(noteText: String, athlete: Athlete, session: CoachSession,
         sessionBlock: SessionBlock? = nil) {
        self.id = UUID()
        self.noteText = noteText
        self.createdAt = Date()
        self.athlete = athlete
        self.session = session
        self.sessionBlock = sessionBlock
    }
}

// MARK: - TechnicalAssessment

/// A technical assessment snapshot for an athlete at a given development stage.
///
/// CloudKit compatibility: see notes on `Athlete`. Hand-rolled cleanup for
/// ratings lives in `ModelContext.deleteAssessmentCascade`.
@Model
class TechnicalAssessment {
    var id: UUID = UUID()
    /// Last local edit time; the basis for last-write-wins backend sync (Phase 2).
    /// Stamped at the SwiftData save chokepoint when this record is created or changed.
    var updatedAt: Date = Date()
    var date: Date = Date()
    var stage: DevelopmentStage = DevelopmentStage.initiation
    var overallNotes: String?
    var createdAt: Date = Date()

    var athlete: Athlete?

    @Relationship(deleteRule: .nullify, inverse: \TechnicalRating.assessment)
    var ratings: [TechnicalRating]?

    /// Creates a new assessment and starts with an empty rating collection.
    init(date: Date = Date(), stage: DevelopmentStage = .initiation, athlete: Athlete? = nil,
         overallNotes: String? = nil) {
        self.id = UUID()
        self.date = date
        self.stage = stage
        self.overallNotes = overallNotes
        self.createdAt = Date()
        self.athlete = athlete
        self.ratings = []
    }

    /// Average rating across all recorded factors.
    var averageScore: Double {
        let scores = ratings ?? []
        guard !scores.isEmpty else { return 0 }
        let total = scores.reduce(0) { $0 + $1.score }
        return Double(total) / Double(scores.count)
    }
}

// MARK: - TechnicalRating

/// A scored factor within a technical assessment.
@Model
class TechnicalRating {
    var id: UUID = UUID()
    /// Last local edit time; the basis for last-write-wins backend sync (Phase 2).
    /// Stamped at the SwiftData save chokepoint when this record is created or changed.
    var updatedAt: Date = Date()
    var category: String = ""
    var factor: String = ""
    var score: Int = 1
    var comment: String?

    var assessment: TechnicalAssessment?

    /// Creates one scored factor and clamps the score to the supported 1...5 range.
    init(category: String, factor: String, score: Int, comment: String? = nil,
         assessment: TechnicalAssessment? = nil) {
        self.id = UUID()
        self.category = category
        self.factor = factor
        self.score = min(max(score, 1), 5)
        self.comment = comment
        self.assessment = assessment
    }
}

// MARK: - RegattaResult

/// Stores a race result used alongside training data for trend analysis.
@Model
class RegattaResult {
    var id: UUID = UUID()
    /// Last local edit time; the basis for last-write-wins backend sync (Phase 2).
    /// Stamped at the SwiftData save chokepoint when this record is created or changed.
    var updatedAt: Date = Date()
    var regattaName: String = ""
    var location: String?
    var regattaDate: Date = Date()
    var eventDistance: Int = 0
    var placement: Int?
    var totalCompetitors: Int?
    var resultTimeMs: Int = 0
    var notes: String?
    var createdAt: Date = Date()

    var athlete: Athlete?

    /// Creates a regatta result for an athlete and event distance.
    init(regattaName: String,
         location: String? = nil,
         regattaDate: Date,
         eventDistance: Int,
         placement: Int? = nil,
         totalCompetitors: Int? = nil,
         resultTimeMs: Int,
         notes: String? = nil,
         athlete: Athlete? = nil) {
        self.id = UUID()
        self.regattaName = regattaName
        self.location = location
        self.regattaDate = regattaDate
        self.eventDistance = eventDistance
        self.placement = placement
        self.totalCompetitors = totalCompetitors
        self.resultTimeMs = resultTimeMs
        self.notes = notes
        self.createdAt = Date()
        self.athlete = athlete
    }

    /// Formatted result time for display in the UI.
    var formattedTime: String {
        formatMillisecondsForDisplay(resultTimeMs)
    }
}

// MARK: - FitnessTestResult

/// Stores the result of a named fitness test for an athlete.
@Model
class FitnessTestResult {
    var id: UUID = UUID()
    /// Last local edit time; the basis for last-write-wins backend sync (Phase 2).
    /// Stamped at the SwiftData save chokepoint when this record is created or changed.
    var updatedAt: Date = Date()
    var testType: String = ""
    var result: Double = 0
    var unit: String = "seconds"
    var testDate: Date = Date()
    var notes: String?
    var createdAt: Date = Date()

    var athlete: Athlete?

    /// Creates a fitness test result using seconds as the default unit.
    init(testType: String,
         result: Double,
         unit: String = "seconds",
         testDate: Date = Date(),
         notes: String? = nil,
         athlete: Athlete? = nil) {
        self.id = UUID()
        self.testType = testType
        self.result = result
        self.unit = unit
        self.testDate = testDate
        self.notes = notes
        self.createdAt = Date()
        self.athlete = athlete
    }

    /// Formatted result time for display in the UI.
    var formattedTime: String {
        formatSecondsForDisplay(result)
    }
}

// MARK: - DevelopmentNote

/// A freeform coaching journal entry for an athlete, with optional topic tags.
@Model
class DevelopmentNote {
    var id: UUID = UUID()
    /// Last local edit time; the basis for last-write-wins backend sync (Phase 2).
    /// Stamped at the SwiftData save chokepoint when this record is created or changed.
    var updatedAt: Date = Date()
    var date: Date = Date()
    var text: String = ""
    var tags: [String] = []
    var createdAt: Date = Date()
    /// Name of the coach who wrote this journal entry, for "logged by" attribution.
    var createdByCoachName: String?
    var athlete: Athlete?

    init(date: Date = Date(), text: String, tags: [String] = [], athlete: Athlete? = nil) {
        self.id = UUID()
        self.date = date
        self.text = text
        self.tags = tags
        self.createdAt = Date()
        self.athlete = athlete
    }
}

// MARK: - KTCAssessment

/// A CKC Kayak Technical Check snapshot for an athlete at a defined seasonal window.
@Model
final class KTCAssessment {
    var id: UUID = UUID()
    /// Last local edit time; the basis for last-write-wins backend sync (Phase 2).
    /// Stamped at the SwiftData save chokepoint when this record is created or changed.
    var updatedAt: Date = Date()
    var date: Date = Date()
    var window: String = ""
    var setupRecoveryScore: Int = 1
    var catchScore: Int = 1
    var propulsionDrawScore: Int = 1
    var exitScore: Int = 1
    var notes: String?
    var createdAt: Date = Date()

    var athlete: Athlete?

    init(date: Date = Date(), window: String,
         setupRecoveryScore: Int, catchScore: Int,
         propulsionDrawScore: Int, exitScore: Int,
         notes: String? = nil, athlete: Athlete? = nil) {
        self.id = UUID()
        self.date = date
        self.window = window
        self.setupRecoveryScore = min(max(setupRecoveryScore, 1), 5)
        self.catchScore = min(max(catchScore, 1), 5)
        self.propulsionDrawScore = min(max(propulsionDrawScore, 1), 5)
        self.exitScore = min(max(exitScore, 1), 5)
        self.notes = notes
        self.createdAt = Date()
        self.athlete = athlete
    }

    var averageScore: Double {
        Double(setupRecoveryScore + catchScore + propulsionDrawScore + exitScore) / 4.0
    }
}

/// The seasonal training windows offered when logging a KTC assessment.
let ktcWindows: [String] = [
    "General Prep 1",
    "General Prep 2",
    "On-Water Return",
    "Specific Prep",
    "Pre-Competition",
    "Post-Competition"
]

// MARK: - HeightRecord

/// Records an athlete's height measurement for PHV (peak height velocity) tracking.
@Model
class HeightRecord {
    var id: UUID = UUID()
    /// Last local edit time; the basis for last-write-wins backend sync (Phase 2).
    /// Stamped at the SwiftData save chokepoint when this record is created or changed.
    var updatedAt: Date = Date()
    var heightCm: Double = 0
    var date: Date = Date()
    var createdAt: Date = Date()
    var athlete: Athlete?

    init(heightCm: Double, date: Date = Date(), athlete: Athlete? = nil) {
        self.id = UUID()
        self.heightCm = heightCm
        self.date = date
        self.createdAt = Date()
        self.athlete = athlete
    }
}

// MARK: - SeasonArchive

/// Captures season summary metrics when completed sessions are archived.
@Model
class SeasonArchive {
    var id: UUID = UUID()
    /// Last local edit time; the basis for last-write-wins backend sync (Phase 2).
    /// Stamped at the SwiftData save chokepoint when this record is created or changed.
    var updatedAt: Date = Date()
    var seasonYear: Int = 0
    var archiveDate: Date = Date()
    var totalAthletes: Int = 0
    var totalSessions: Int = 0
    var totalKm: Double = 0
    var notes: String?

    /// Creates an archive snapshot for a completed season.
    init(seasonYear: Int,
         archiveDate: Date = Date(),
         totalAthletes: Int,
         totalSessions: Int,
         totalKm: Double,
         notes: String? = nil) {
        self.id = UUID()
        self.seasonYear = seasonYear
        self.archiveDate = archiveDate
        self.totalAthletes = totalAthletes
        self.totalSessions = totalSessions
        self.totalKm = totalKm
        self.notes = notes
    }
}

// MARK: - Coach

/// A coach profile for the club. Identifies who is using the app on this device
/// and provides the name stamped onto records as "logged by" attribution.
///
/// Stored in the shared SwiftData store so all of a coach's own devices — and,
/// when a club shares one iCloud account, all coaches — see the same roster.
///
/// CloudKit compatibility: see notes on `Athlete` — every non-optional stored
/// property has a declaration-level default.
@Model
final class Coach {
    var id: UUID = UUID()
    /// Last local edit time; the basis for last-write-wins backend sync (Phase 2).
    /// Stamped at the SwiftData save chokepoint when this record is created or changed.
    var updatedAt: Date = Date()
    var name: String = ""
    var role: String?
    var nccpLevel: String?
    var colorHex: String?
    var createdAt: Date = Date()

    /// Creates a coach profile, auto-assigning a palette color when none is given.
    init(name: String, role: String? = nil, nccpLevel: String? = nil, colorHex: String? = nil) {
        self.id = UUID()
        self.name = name
        self.role = role
        self.nccpLevel = nccpLevel
        self.colorHex = colorHex ?? Coach.palette.randomElement()
        self.createdAt = Date()
    }

    /// Up to two uppercase initials derived from the name, for the attribution chip.
    var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    /// Display color resolved from `colorHex`, falling back to the app accent.
    var displayColor: Color {
        Color(hex: colorHex) ?? .accentColor
    }

    /// Fixed palette of legible colors auto-assigned to new coaches.
    static let palette: [String] = [
        "#3B82F6", "#10B981", "#F59E0B", "#EF4444",
        "#8B5CF6", "#EC4899", "#06B6D4", "#F97316"
    ]
}

/// Common NCCP coaching certification levels offered when creating a coach profile.
let nccpLevels: [String] = [
    "Community Coach",
    "Competition Introduction",
    "Competition Development",
    "Competition High Performance"
]

extension Color {
    /// Creates a color from a `#RRGGBB` hex string. Returns nil for malformed input.
    init?(hex: String?) {
        guard let hex else { return nil }
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}

// MARK: - Enums

/// High-level categories for workout blocks. Each case maps to a specific
/// input form in `AddBlockSheet` and a specific logger UI in `BlockEntryPhaseView`.
enum BlockType: String, Codable, CaseIterable {
    // Paddle on water
    case paddleDistance        = "Paddle Distance"
    case paddleTimePieces      = "Paddle Time Pieces"
    case paddlePyramid         = "Paddle Pyramid"
    // Run on land
    case runDistance           = "Run Distance"
    case runIntervals          = "Run Intervals"
    // Strength / land training
    case weights               = "Weights"
    case circuit               = "Circuit"
    case core                  = "Core"
    // Session structure
    case technique             = "Technique"

    /// True for block types whose logger UI captures per-rep data per athlete
    /// via pre-generated `PerformanceRecord` slots. Note-driven land blocks
    /// (weights/circuit/core) and structural blocks (technique) don't use
    /// slots. Single source of truth for slot generation (`AddBlockSheet`),
    /// backfill/pruning (`SessionLoggerView`), and edit-guard logic.
    var capturesPerRepData: Bool {
        switch self {
        case .paddleDistance, .paddleTimePieces, .paddlePyramid,
             .runDistance, .runIntervals:
            return true
        case .weights, .circuit, .core, .technique:
            return false
        }
    }
}

/// Lifecycle status for a pre-generated rep entry slot.
enum RepEntryStatus: String, Codable, CaseIterable {
    case pending  = "Pending"
    case complete = "Complete"
    case dns      = "DNS"
    case dnf      = "DNF"
}

/// Lifecycle states for a training session.
///
/// A session is `.open` until the coach marks it `.completed` or `.cancelled`.
/// The former `.scheduled` / `.inProgress` states were collapsed into `.open` —
/// the dashboard buckets open sessions by date, not by status.
///
/// Persistence: the `RawRepresentable` conformance is total — `init(rawValue:)`
/// never fails. Legacy stored values `"Scheduled"` / `"In Progress"` (still
/// present in local stores and in CloudKit, and still written by any un-updated
/// v1.1 device) decode to `.open`. `.open` deliberately re-encodes as the raw
/// string `"Scheduled"` so records this build writes stay decodable by a v1.1
/// build — CloudKit sync remains compatible in both directions.
enum SessionStatus: Codable, CaseIterable, Hashable {
    case open
    case completed
    case cancelled

    /// True for any session that is not yet completed or cancelled.
    var isOpen: Bool { self == .open }
}

extension SessionStatus: RawRepresentable {
    nonisolated init(rawValue: String) {
        switch rawValue {
        case "Completed": self = .completed
        case "Cancelled": self = .cancelled
        default:          self = .open   // "Scheduled", "In Progress", or anything unknown
        }
    }

    nonisolated var rawValue: String {
        switch self {
        case .open:      return "Scheduled"   // wire-compatible with shipped v1.1 builds
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }
}

extension SessionStatus {
    // `nonisolated` on the persistence witnesses: SessionStatus is a pure
    // value type, and SwiftData/CloudKit may invoke encode/decode from
    // background queues. Without this, the project's MainActor default would
    // produce a "main actor-isolated conformance" warning.
    nonisolated init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Attendance outcomes captured during session logging.
enum AttendanceStatus: String, Codable, CaseIterable {
    case present = "Present"
    case absent  = "Absent"
    case excused = "Excused"
}

/// Athlete gender values used by fitness benchmark lookups.
enum Gender: String, Codable, CaseIterable {
    case male   = "Male"
    case female = "Female"
}

/// Training intensity zones used for block planning and load summaries.
enum TrainingZone: String, Codable, CaseIterable {
    case ga1      = "Ga-1"
    case ga2      = "Ga-2"
    case e1       = "E-1"
    case e2       = "E-2"
    case anMix    = "AN Mix"
    case alactic  = "Alactic"
    case recovery = "Recovery"

    var description: String {
        switch self {
        case .ga1:      return "Aerobic Capacity — 70–80% HR"
        case .ga2:      return "Aerobic Capacity — 80–85% HR"
        case .e1:       return "Aerobic Power — 85–95% HR"
        case .e2:       return "Aerobic Power — 95–100% HR"
        case .anMix:    return "Speed Endurance — Max HR"
        case .alactic:  return "Alactic Speed — Max"
        case .recovery: return "Recovery / Technical — <65% HR"
        }
    }

    var color: Color {
        switch self {
        case .ga1:      return .readableBlue
        case .ga2:      return .readableCyan
        case .e1:       return .readableOrange
        case .e2:       return .readableRed
        case .anMix:    return .readablePurple
        case .alactic:  return .readablePink
        case .recovery: return .readableGreen
        }
    }
}

/// Long-term athlete development stages used by technical assessments.
enum DevelopmentStage: String, Codable, CaseIterable {
    case initiation = "Initiation"
    case acquisition = "Acquisition"
    case consolidation = "Consolidation"
    case refinement = "Refinement"
}

// MARK: - SessionStatus UI helpers

/// UI helpers for presenting session states consistently across the app.
extension SessionStatus {
    /// Accent color for completed and cancelled states; open sessions have no badge.
    var color: Color {
        switch self {
        case .open:      return .clear
        case .completed: return .readableGray
        case .cancelled: return .readableRed
        }
    }
}

// MARK: - PendingChange (sync outbox)

/// The kind of local change an outbox entry records.
enum SyncOperation: String, Codable, CaseIterable {
    case insert
    case update
    case delete
}

/// Lifecycle of an outbox entry as the pusher drains the queue.
enum PendingChangeStatus: String, Codable, CaseIterable {
    case pending
    case inFlight
    case failed
}

/// Outbox entry: one local change awaiting push to the backend.
///
/// Local-only — a `PendingChange` is never synced to the backend or across
/// devices; it is the queue that drives the push half of last-write-wins sync.
/// Rows are written at the SwiftData save chokepoint (Stage 3b) and removed once
/// the pusher confirms the change landed. It deliberately has no `updatedAt`
/// (it is not a synced domain record); `enqueuedAt` orders the queue.
@Model
final class PendingChange {
    var id: UUID = UUID()
    /// The synced model's type name (e.g. "Athlete"), used to route the push.
    var entityType: String = ""
    /// The synced model's stable `id`, so the pusher can re-fetch it from the store.
    var entityId: UUID = UUID()
    var operation: SyncOperation = SyncOperation.update
    var enqueuedAt: Date = Date()
    var status: PendingChangeStatus = PendingChangeStatus.pending

    init(entityType: String, entityId: UUID, operation: SyncOperation, enqueuedAt: Date = Date()) {
        self.id = UUID()
        self.entityType = entityType
        self.entityId = entityId
        self.operation = operation
        self.enqueuedAt = enqueuedAt
        self.status = .pending
    }
}
