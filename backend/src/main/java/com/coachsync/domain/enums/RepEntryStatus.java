package com.coachsync.domain.enums;

/**
 * State of a single per-athlete rep slot on a {@code PerformanceRecord}.
 * PENDING = slot generated, no result yet; DNS = did not start; DNF = did not finish.
 */
public enum RepEntryStatus {
    PENDING,
    COMPLETE,
    DNS,
    DNF
}
