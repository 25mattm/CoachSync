package com.coachsync.domain;

import java.time.Instant;
import java.time.temporal.ChronoUnit;

/**
 * Instants at the precision the timestamp columns store: microseconds.
 *
 * <p>{@link Instant#now()} carries nanoseconds on Linux, which the database rounds away on
 * store. An entity stamped with the raw value would return one time from the write that
 * created it and a slightly different one from every later read. Every server-side stamp
 * goes through here instead, so the API returns exactly what is stored.
 */
public final class Timestamps {

    private Timestamps() {
    }

    /** Now, truncated to microseconds. */
    public static Instant now() {
        return Instant.now().truncatedTo(ChronoUnit.MICROS);
    }

    /** {@code instant} truncated to microseconds, or {@code null}. */
    public static Instant atColumnPrecision(Instant instant) {
        return instant == null ? null : instant.truncatedTo(ChronoUnit.MICROS);
    }
}
