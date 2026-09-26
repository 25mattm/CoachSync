import Foundation
import SwiftData
@testable import CoachSync

/// Shared scaffolding for SwiftData-backed unit tests.
enum TestSupport {

    /// The full production model schema — all 16 `@Model` types, mirroring the
    /// `Schema` registered in `CoachSyncApp` / `CoachSyncMacApp`.
    static let schema = Schema([
        Athlete.self,
        Team.self,
        TeamMembership.self,
        CoachSession.self,
        SessionBlock.self,
        AttendanceRecord.self,
        PerformanceRecord.self,
        AthleteNote.self,
        FitnessTestResult.self,
        RegattaResult.self,
        SeasonArchive.self,
        TechnicalAssessment.self,
        TechnicalRating.self,
        DevelopmentNote.self,
        HeightRecord.self,
        KTCAssessment.self
    ])

    /// Builds a fresh, empty, in-memory `ModelContext` for a hermetic test.
    /// The returned context retains its container, so callers keep only the context.
    static func makeInMemoryContext() throws -> ModelContext {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }
}
