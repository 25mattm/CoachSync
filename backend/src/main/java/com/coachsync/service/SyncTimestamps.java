package com.coachsync.service;

import com.coachsync.domain.BaseEntity;

import java.time.Duration;
import java.time.Instant;

/**
 * Last-write-wins (LWW) timestamp helpers shared by the write services (Phase 2).
 *
 * <p>{@code updatedAt} is client-authoritative: the iOS app stamps it at its local
 * save chokepoint and sends it on every write. A write is accepted only when it is
 * strictly newer than what is stored; otherwise it is ignored ("skip-stale"). A
 * missing incoming timestamp (a legacy / non-sync caller) is treated as "always
 * apply" and stamped with {@link Instant#now()}.
 *
 * <p><b>Future timestamps are capped.</b> A device whose clock runs ahead would otherwise
 * store a future {@code updatedAt} that no correctly-clocked device could ever beat, freezing
 * the row until real time caught up. So an incoming stamp more than {@link #MAX_CLOCK_SKEW}
 * ahead of the server is treated as "now", and a stored stamp that far ahead (written before
 * this cap existed) never blocks a write — the next accepted write replaces it.
 */
final class SyncTimestamps {

    /** How far ahead of the server a client clock may run before its stamp is distrusted. */
    static final Duration MAX_CLOCK_SKEW = Duration.ofMinutes(5);

    private SyncTimestamps() {
    }

    /**
     * True when an incoming write should be ignored because it is not newer than the
     * stored record. A {@code null} incoming timestamp never counts as stale, and neither
     * does anything written over a stored stamp that is implausibly far in the future.
     */
    static boolean isStale(BaseEntity stored, Instant incoming) {
        return incoming != null
                && stored.getUpdatedAt() != null
                && !isBeyondSkew(stored.getUpdatedAt())
                && !resolve(incoming).isAfter(stored.getUpdatedAt());
    }

    /**
     * The timestamp to stamp on an accepted write: the client's, or now if absent or
     * implausibly far in the future.
     */
    static Instant resolve(Instant incoming) {
        return incoming != null && !isBeyondSkew(incoming) ? incoming : Instant.now();
    }

    private static boolean isBeyondSkew(Instant timestamp) {
        return timestamp.isAfter(Instant.now().plus(MAX_CLOCK_SKEW));
    }
}
