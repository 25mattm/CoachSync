/// The single SwiftData save chokepoint (Phase 2 Stage 3b) — the push half of last-write-wins sync.
///
/// Every live-store mutation in the app commits through `SyncStore.save(_:)` instead of
/// `ModelContext.save()`. Before committing, the chokepoint:
///  1. stamps `updatedAt = .now` on each inserted or changed synced model, and
///  2. records one `PendingChange` outbox row per inserted / changed / deleted synced model,
/// so the data write and its outbox entries land in the same transaction. A later pusher drains
/// the outbox to the backend.
///
/// The Stage-3c backend → live-store pull writes through a separate, non-enqueuing path: pulled
/// rows must not be re-stamped or re-queued (they originated on the server).

import Foundation
import OSLog
import SwiftData

/// A SwiftData model that participates in backend sync.
///
/// Conformers are captured by the `SyncStore` chokepoint and have their `updatedAt` stamped on
/// every local insert/change. The app-only `SeasonArchive` and the outbox's own `PendingChange`
/// deliberately do NOT conform — they never sync.
protocol SyncedModel: AnyObject {
    var id: UUID { get set }
    var updatedAt: Date { get set }
    /// Stable type tag stored on the outbox row to route the push. Matches the model type name.
    static var syncEntityName: String { get }
}

extension Athlete: SyncedModel { static var syncEntityName: String { "Athlete" } }
extension Team: SyncedModel { static var syncEntityName: String { "Team" } }
extension TeamMembership: SyncedModel { static var syncEntityName: String { "TeamMembership" } }
extension CoachSession: SyncedModel { static var syncEntityName: String { "CoachSession" } }
extension SessionBlock: SyncedModel { static var syncEntityName: String { "SessionBlock" } }
extension AttendanceRecord: SyncedModel { static var syncEntityName: String { "AttendanceRecord" } }
extension PerformanceRecord: SyncedModel { static var syncEntityName: String { "PerformanceRecord" } }
extension AthleteNote: SyncedModel { static var syncEntityName: String { "AthleteNote" } }
extension TechnicalAssessment: SyncedModel { static var syncEntityName: String { "TechnicalAssessment" } }
// TechnicalRating is deliberately NOT a SyncedModel: ratings are a replace-all sub-aggregate
// synced inside the assessment's body (and are create-only in the app), so they never push or
// enqueue on their own — the parent assessment's POST/PUT carries them.
extension RegattaResult: SyncedModel { static var syncEntityName: String { "RegattaResult" } }
extension FitnessTestResult: SyncedModel { static var syncEntityName: String { "FitnessTestResult" } }
extension DevelopmentNote: SyncedModel { static var syncEntityName: String { "DevelopmentNote" } }
extension KTCAssessment: SyncedModel { static var syncEntityName: String { "KTCAssessment" } }
extension HeightRecord: SyncedModel { static var syncEntityName: String { "HeightRecord" } }
extension Coach: SyncedModel { static var syncEntityName: String { "Coach" } }

enum SyncStore {

    /// Posted after a save that enqueued at least one outbox row, so a `SyncCoordinator` can
    /// debounce a push-then-pull. Carries no payload.
    static let didSaveNotification = Notification.Name("CoachSync.SyncStore.didSave")

    /// Commits the context's pending changes through the outbox. Use everywhere the app would
    /// otherwise call `modelContext.save()` for a user edit.
    static func save(_ context: ModelContext) throws {
        let enqueued = enqueueOutbox(in: context)
        try context.save()
        if enqueued {
            NotificationCenter.default.post(name: didSaveNotification, object: nil)
        }
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CoachSync",
                                       category: "persistence")

    /// `save(_:)` for background housekeeping the coach can't act on (draft sweeps, slot
    /// backfill): a failure is logged instead of thrown. User-initiated saves must call
    /// `save(_:)` and surface the error. This is the only sanctioned way to not propagate one.
    static func saveLoggingFailure(_ context: ModelContext, _ operation: StaticString) {
        do {
            try save(context)
        } catch {
            logger.error("\(operation, privacy: .public) save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stamps `updatedAt` and records `PendingChange` rows for the context's currently-pending
    /// inserts, changes, and deletes; returns whether anything was enqueued. Exposed (not private)
    /// so it can be unit-tested directly. Non-synced models (`SeasonArchive`, `PendingChange`) are skipped.
    @discardableResult
    static func enqueueOutbox(in context: ModelContext, now: Date = Date()) -> Bool {
        // Snapshot the pending sets first: stamping `updatedAt` and inserting `PendingChange`
        // rows mutates the context, which would otherwise change these collections mid-iteration.
        let inserted = context.insertedModelsArray
        let changed = context.changedModelsArray
        let deleted = context.deletedModelsArray

        var enqueued = false
        for model in inserted { enqueued = record(model, op: .insert, stamp: true, now: now, in: context) || enqueued }
        // KNOWN LIMITATION — parent-touch LWW churn (documented, not fixed; single-coach use is unaffected).
        // SwiftData marks a parent "changed" when a child is inserted/removed (the inverse to-many is
        // touched) even if the parent's own attributes are untouched, so logging attendance or adding a
        // block enqueues a parent UPDATE carrying this device's view of the parent — which can revert a
        // concurrent cross-coach edit to e.g. sessionName/teamNote/mfCue. Filtering to a real attribute
        // change is NOT cleanly possible pre-save: PersistentModel/BackingData expose no changed-keys API,
        // the backing NSManagedObject (changedValues/hasPersistentChangedValues) is unreachable, and the
        // only per-attribute signal — HistoryUpdate.updatedAttributes — lives in the post-save persistent-
        // history mechanism this explicit outbox deliberately avoids. The naive "skip a parent that has a
        // child insert this batch" heuristic is unsafe: it would drop a legitimate parent edit saved in
        // the same transaction (AddBlockSheet edits a block AND prunes its slots). See the characterization
        // test `testChildInsertAlsoEnqueuesParent_knownLimitation`.
        for model in changed { enqueued = record(model, op: .update, stamp: true, now: now, in: context) || enqueued }
        for model in deleted { enqueued = record(model, op: .delete, stamp: false, now: now, in: context) || enqueued }
        return enqueued
    }

    @discardableResult
    private static func record(_ model: any PersistentModel, op: SyncOperation,
                               stamp: Bool, now: Date, in context: ModelContext) -> Bool {
        // Skips PendingChange + SeasonArchive (neither conforms to SyncedModel).
        guard let synced = model as? any SyncedModel else { return false }
        if stamp { synced.updatedAt = now }
        let change = PendingChange(entityType: type(of: synced).syncEntityName,
                                   entityId: synced.id, operation: op)
        context.insert(change)
        return true
    }
}
