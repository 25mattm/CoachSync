package com.coachsync.service;

import com.coachsync.domain.Athlete;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;

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
        Instant slightlyAhead = Instant.now().plus(Duration.ofMinutes(1)).truncatedTo(ChronoUnit.MICROS);
        assertEquals(slightlyAhead, SyncTimestamps.resolve(slightlyAhead));
    }

    @Test
    void aStampIsTruncatedToTheColumnsMicrosecondPrecision() {
        Instant withNanos = Instant.parse("2026-10-29T12:00:00.123456789Z");
        assertEquals(Instant.parse("2026-10-29T12:00:00.123456Z"), SyncTimestamps.resolve(withNanos));
        assertEquals(0, SyncTimestamps.resolve(null).getNano() % 1_000, "now must be stamped at microseconds");
    }

    @Test
    void reSendingTheStoredStampIsStale() {
        // The client echoes back what the server returned; that must not count as a newer write.
        Instant withNanos = Instant.parse("2026-10-29T12:00:00.123456789Z");
        Athlete stored = storedAt(SyncTimestamps.resolve(withNanos));
        assertTrue(SyncTimestamps.isStale(stored, withNanos));
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
