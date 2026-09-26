/// Encodable mirrors of the backend `*Request` shapes, used by the write-sync (Stage 3b) push.
/// Field names match the backend records exactly so `JSONEncoder` produces the bodies the API
/// expects. Dates are pre-formatted to the backend's string shapes in `SyncPushMapping`
/// (`LocalDate` → "yyyy-MM-dd", `LocalDateTime` → "yyyy-MM-dd'T'HH:mm:ss", `Instant` → ISO-8601),
/// and enums are sent as the backend's UPPER_SNAKE names — so every field here is a plain scalar.
///
/// `id` is the app's own model id (id-matched sync: the backend persists it via POST-with-id).
/// `updatedAt` is the client edit time that drives last-write-wins.

import Foundation

struct AthleteRequestDTO: Encodable {
    let id: UUID
    let firstName: String
    let lastName: String
    let dateOfBirth: String
    let gender: String?
    let guardianName: String?
    let guardianPhone: String?
    let guardianEmail: String?
    let developmentStage: String
    let active: Bool
    let updatedAt: String
}

struct TeamRequestDTO: Encodable {
    let id: UUID
    let teamName: String
    let teamDescription: String?
    let archived: Bool
    let updatedAt: String
}

struct TeamMembershipRequestDTO: Encodable {
    let id: UUID
    let athleteId: UUID
    let joinedDate: String?
    let leftDate: String?
    let updatedAt: String
}

struct SessionRequestDTO: Encodable {
    let id: UUID
    let sessionName: String
    let scheduledDate: String
    let startTime: String?
    let endTime: String?
    let weatherNote: String?
    let teamNote: String?
    let sessionNote: String?
    let mfCue: String?
    let teamId: UUID?
    let status: String
    let archived: Bool
    let updatedAt: String
}

struct BlockRequestDTO: Encodable {
    let id: UUID
    let blockName: String
    let blockType: String
    let sortOrder: Int
    let repetitionCount: Int
    let setCount: Int
    let targetDistanceMetres: Double?
    let distanceKm: Double?
    let restIntervalSeconds: Int?
    let durationSeconds: Int?
    let requiresTimeEntry: Bool
    let trainingZone: String?
    let drillName: String?
    let coachNote: String?
    let prescribedRepDurationsSec: [Int]?
    let updatedAt: String
}

/// Note create (POST under a session). Attribution comes from the JWT principal, not this body.
struct NoteCreateRequestDTO: Encodable {
    let id: UUID
    let athleteId: UUID
    let noteText: String
    let sessionBlockId: UUID?
    let updatedAt: String
}

/// Note update (PUT by id). Athlete, session, and the original "logged by" coach are fixed.
struct NoteUpdateRequestDTO: Encodable {
    let noteText: String
    let sessionBlockId: UUID?
    let updatedAt: String
}

struct RatingRequestDTO: Encodable {
    let category: String
    let factor: String
    let score: Int
    let comment: String?
}

struct AssessmentRequestDTO: Encodable {
    let id: UUID
    let date: String
    let stage: String
    let overallNotes: String?
    let ratings: [RatingRequestDTO]
    let updatedAt: String
}

struct FitnessTestRequestDTO: Encodable {
    let id: UUID
    let testType: String
    let result: Double
    let unit: String
    let testDate: String
    let notes: String?
    let updatedAt: String
}

struct RegattaResultRequestDTO: Encodable {
    let id: UUID
    let regattaName: String
    let location: String?
    let regattaDate: String
    let eventDistanceMetres: Int
    let placement: Int?
    let totalCompetitors: Int?
    let resultTimeMs: Int
    let notes: String?
    let updatedAt: String
}

struct JournalRequestDTO: Encodable {
    let id: UUID
    let date: String
    let text: String
    let tags: [String]
    let updatedAt: String
}

struct KtcRequestDTO: Encodable {
    let id: UUID
    let date: String
    let window: String
    let setupRecoveryScore: Int
    let catchScore: Int
    let propulsionDrawScore: Int
    let exitScore: Int
    let notes: String?
    let updatedAt: String
}

struct HeightRecordRequestDTO: Encodable {
    let id: UUID
    let heightCm: Double
    let date: String
    let updatedAt: String
}

struct CoachRequestDTO: Encodable {
    let id: UUID
    let name: String
    let role: String?
    let nccpLevel: String?
    let colorHex: String?
    let updatedAt: String
}

/// Bulk attendance upsert (`PUT /sessions/{id}/attendance`). The app pushes one entry per record.
struct AttendanceUpdateRequestDTO: Encodable {
    let entries: [AttendanceEntryDTO]
}

struct AttendanceEntryDTO: Encodable {
    let id: UUID
    let athleteId: UUID
    let status: String
    let absenceReason: String?
    let updatedAt: String
}

/// Natural-key rep-result upsert (`PUT /blocks/{id}/performance`). Matched by athlete + rep, not id.
struct PerformanceUpsertRequestDTO: Encodable {
    let entries: [PerformanceUpsertEntryDTO]
}

struct PerformanceUpsertEntryDTO: Encodable {
    let athleteId: UUID
    let repNumber: Int
    let status: String
    let recordedTimeMs: Int?
    let updatedAt: String
}
