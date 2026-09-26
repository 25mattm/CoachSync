/// Codable mirrors of the backend `*Response` shapes, used by the sync pull.
/// Field names match the backend records exactly so `JSONDecoder.backend` decodes them.
///
/// Date handling: the backend serializes `Instant` (`createdAt`/`updatedAt`) as ISO-8601 date-time
/// (decoded as `Date` by `JSONDecoder.backend`); `LocalDate`/`LocalDateTime` fields arrive as bare
/// `"yyyy-MM-dd"` / `"yyyy-MM-dd'T'HH:mm:ss"` strings, kept as `String` here and parsed in
/// `SyncMapping`. `updatedAt` drives last-write-wins on merge into the live store.

import Foundation

/// Spring `PagedModel` envelope: `{ content: [...], page: { ... } }`.
struct PageDTO<Element: Decodable>: Decodable {
    let content: [Element]
    let page: PageInfo?

    struct PageInfo: Decodable {
        let size: Int
        let number: Int
        let totalElements: Int
        let totalPages: Int
    }
}

struct AthleteDTO: Decodable, Identifiable {
    let id: UUID
    let firstName: String
    let lastName: String
    let dateOfBirth: String          // LocalDate
    let gender: String?
    let guardianName: String?
    let guardianPhone: String?
    let guardianEmail: String?
    let active: Bool
    let developmentStage: String
    let createdAt: Date              // Instant
    let updatedAt: Date
}

struct TeamDTO: Decodable, Identifiable {
    let id: UUID
    let teamName: String
    let teamDescription: String?
    let archived: Bool
    let createdAt: Date
    let updatedAt: Date
}

struct TeamMembershipDTO: Decodable, Identifiable {
    let id: UUID
    let athleteId: UUID
    let teamId: UUID
    let joinedDate: String           // LocalDate
    let leftDate: String?            // LocalDate
    let updatedAt: Date
}

struct SessionDTO: Decodable, Identifiable {
    let id: UUID
    let sessionName: String
    let scheduledDate: String        // LocalDate
    let startTime: String?           // LocalDateTime
    let endTime: String?             // LocalDateTime
    let status: String
    let weatherNote: String?
    let teamNote: String?
    let sessionNote: String?
    let mfCue: String?
    let archived: Bool
    let coachId: UUID?
    let teamId: UUID?
    let createdAt: Date
    let updatedAt: Date
}

struct BlockDTO: Decodable, Identifiable {
    let id: UUID
    let sessionId: UUID
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
    let prescribedRepDurationsSec: [Int]
    let updatedAt: Date
}

struct AttendanceDTO: Decodable, Identifiable {
    let id: UUID
    let athleteId: UUID
    let status: String
    let absenceReason: String?
    let updatedAt: Date
}

struct PerformanceDTO: Decodable, Identifiable {
    let id: UUID
    let athleteId: UUID
    let repNumber: Int
    let recordedTimeMs: Int?
    let status: String
    let updatedAt: Date
}

struct NoteDTO: Decodable, Identifiable {
    let id: UUID
    let noteText: String
    let createdAt: Date
    let athleteId: UUID
    let sessionId: UUID
    let sessionBlockId: UUID?
    let coachId: UUID?
    let updatedAt: Date
}

struct AssessmentDTO: Decodable, Identifiable {
    let id: UUID
    let athleteId: UUID
    let date: String                 // LocalDate
    let stage: String
    let overallNotes: String?
    let createdAt: Date
    let updatedAt: Date
    let ratings: [RatingDTO]
}

struct RatingDTO: Decodable, Identifiable {
    let id: UUID
    let category: String
    let factor: String
    let score: Int
    let comment: String?
}

struct FitnessTestDTO: Decodable, Identifiable {
    let id: UUID
    let athleteId: UUID
    let testType: String
    let result: Double
    let unit: String
    let testDate: String             // LocalDate
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
}

struct RegattaResultDTO: Decodable, Identifiable {
    let id: UUID
    let athleteId: UUID
    let regattaName: String
    let location: String?
    let regattaDate: String          // LocalDate
    let eventDistanceMetres: Int
    let placement: Int?
    let totalCompetitors: Int?
    let resultTimeMs: Int
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
}

struct JournalDTO: Decodable, Identifiable {
    let id: UUID
    let athleteId: UUID
    let date: String                 // LocalDate
    let text: String
    let tags: [String]
    let coachId: UUID?
    let createdAt: Date
    let updatedAt: Date
}

struct KtcDTO: Decodable, Identifiable {
    let id: UUID
    let athleteId: UUID
    let date: String                 // LocalDate
    let window: String
    let setupRecoveryScore: Int
    let catchScore: Int
    let propulsionDrawScore: Int
    let exitScore: Int
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
}

struct HeightRecordDTO: Decodable, Identifiable {
    let id: UUID
    let athleteId: UUID
    let heightCm: Double
    let date: String                 // LocalDate
    let createdAt: Date
    let updatedAt: Date
}
