package com.coachsync.service;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Component;

import java.util.UUID;

/**
 * Runs slot reconciliation for a session AFTER a write (block edit or attendance
 * change) has committed. Being a separate, non-transactional bean means each
 * {@link SlotGenerationService#reconcileSession} call goes through the proxy and
 * gets its own transaction — so a concurrent-reconcile race that loses to the
 * {@code uq_performance_block_athlete_rep} constraint can be retried as a fresh,
 * now-idempotent pass rather than surfacing as a 500.
 */
@Component
public class ReconcileCoordinator {

    private final SlotGenerationService slotGeneration;

    public ReconcileCoordinator(SlotGenerationService slotGeneration) {
        this.slotGeneration = slotGeneration;
    }

    /**
     * Reconciles the session's rep slots, retrying once if a concurrent reconcile
     * loses to the unique-slot constraint (the retry is idempotent).
     */
    public void reconcile(UUID sessionId) {
        try {
            slotGeneration.reconcileSession(sessionId);
        } catch (DataIntegrityViolationException concurrentReconcile) {
            slotGeneration.reconcileSession(sessionId);
        }
    }
}
