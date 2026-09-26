package com.coachsync.service;

import com.coachsync.domain.Athlete;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.Instant;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** Last-write-wins timestamp rules, including the cap on clocks running ahead of the server. */
class SyncTimestampsTest {

    private static Athlete storedAt(Instant updatedAt) {
        Athlete athlete = new Athlete();
        athlete.setUpdatedAt(updatedAt);
        return athlete;
    }

    @Test
    void anOlderWriteIsStaleAndANewerOneIsNot() {
        Instant now = Instant.now();
        Athlete stored = storedAt(now.minus(Duration.ofHours(1)));
        assertTrue(SyncTimestamps.isStale(stored, now.minus(Duration.ofHours(2))));
        assertFalse(SyncTimestamps.isStale(stored, now));
    }

    @Test
    void aStampWithinTheSkewAllowanceIsKeptVerbatim() {
        Instant slightlyAhead = Instant.now().plus(Duration.ofMinutes(1));
        assertEquals(slightlyAhead, SyncTimestamps.resolve(slightlyAhead));
    }

    @Test
    void aStampFarInTheFutureIsReplacedWithNow() {
        Instant tomorrow = Instant.now().plus(Duration.ofDays(1));
        Instant resolved = SyncTimestamps.resolve(tomorrow);
        assertFalse(resolved.isAfter(Instant.now()), "a far-future stamp must be stored as the server's now");
    }

    @Test
    void aFarFutureStoredStampNeverBlocksAWrite() {
        // Written before the cap existed: without this, the row would be frozen until 2099.
        Athlete poisoned = storedAt(Instant.parse("2099-01-01T00:00:00Z"));
        assertFalse(SyncTimestamps.isStale(poisoned, Instant.now()));
    }
}
