/// Drives a full sync cycle (Stage 3c): **push then pull**, so local edits land on the backend
/// before the pull's snapshot-diff runs (otherwise an un-pushed local create could be diff-deleted).
///
/// Triggers (wired in the app): sign-in, launch/foreground, a debounced run after a `SyncStore` save,
/// and the manual "Sync now" button. Concurrent runs are coalesced; `requestSync` debounces bursts.

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SyncCoordinator {

    enum Status: Equatable {
        case idle
        case syncing
        /// `stuckCount` is how many outbox changes the backend definitively rejected (a
        /// non-retriable 4xx) and are left pending rather than silently dropped or falsely
        /// reported as synced.
        case success(Date, stuckCount: Int)
        case failed(String)
        case needsReauth
    }

    private(set) var status: Status = .idle

    private let context: ModelContext
    private let client: BackendClient
    private let tokenProvider: () -> String?
    private let clubIdProvider: () -> UUID?
    private let clubMarker: ClubMarkerStoring
    private var debounceTask: Task<Void, Never>?
    /// A trigger that fired while a sync was already in flight — flushed by a follow-up run so the
    /// edit doesn't sit in the outbox until some unrelated trigger fires.
    private var pendingRequest = false

    init(context: ModelContext,
         client: BackendClient = BackendClient(),
         tokenProvider: @escaping () -> String?,
         clubIdProvider: @escaping () -> UUID? = { nil },
         clubMarker: ClubMarkerStoring = UserDefaultsClubMarker()) {
        self.context = context
        self.client = client
        self.tokenProvider = tokenProvider
        self.clubIdProvider = clubIdProvider
        self.clubMarker = clubMarker
    }

    /// Push the outbox, then pull the club. No-ops (without error) when signed out, already
    /// syncing, or under UI testing.
    func syncNow() async {
        // The single chokepoint every sync trigger funnels through. A UI-test run holds a seeded
        // in-memory store; without this it would push that throwaway data to the live backend (and
        // pull the real club back) on any machine whose Keychain holds a session.
        guard !AppEnvironment.isUITesting else { return }
        guard let token = tokenProvider() else { return }
        if status == .syncing {
            pendingRequest = true  // coalesce: flush this trigger once the in-flight run finishes
            return
        }
        status = .syncing
        do {
            // Club-change / removal guard (multi-club tenancy slice 6): a fresh sign-in that
            // carries a different (or nil) clubId than the one this device last synced under
            // means "this device's local data belongs to a club it's no longer in." Wipe before
            // pushing, so a stale outbox entry can never land on the wrong club — the marker is
            // only advanced once the wipe (or a no-op skip) fully commits, so a thrown wipe error
            // retries on the next sync instead of being silently skipped. A bare 401/needsReauth
            // must NOT trigger this — it's also the ordinary 30-day token-expiry signal, unrelated
            // to club membership, and only a genuine fresh sign-in response updates clubIdProvider.
            let currentClubId = clubIdProvider()
            if let lastClubId = clubMarker.clubId, lastClubId != currentClubId {
                try LocalWipe.wipeAll(in: context)
            }
            clubMarker.clubId = currentClubId
            let stuckCount = try await SyncPusher(client: client, token: token, context: context).push()
            try await SyncService(client: client).pull(into: context, token: token)
            status = .success(Date(), stuckCount: stuckCount)
        } catch SyncPusher.PushError.reauthRequired {
            status = .needsReauth
        } catch BackendError.unauthorized {
            // A 401 from the pull half is also a re-auth signal (the pusher surfaces its own as
            // reauthRequired); don't bury it under the generic "check connection" failure.
            status = .needsReauth
        } catch {
            status = .failed("Sync failed — check the connection and that the backend is reachable.")
        }
        if pendingRequest {
            pendingRequest = false
            requestSync()  // a trigger arrived mid-run — schedule a debounced follow-up to flush it
        }
    }

    /// Debounced trigger for bursty sources (a save, foregrounding). Collapses a burst into one run.
    func requestSync(after delay: Duration = .seconds(2)) {
        guard tokenProvider() != nil else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }
}
