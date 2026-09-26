package com.coachsync.web.dto;

/**
 * One focus area from an athlete's latest technical assessment (a factor scoring
 * &le; 2), with how many recent journal entries cover it. {@code covered} is
 * {@code noteCount > 0} — a {@code false} is an uncovered development gap.
 */
public record DevelopmentCoverageEntry(
        String category,
        String factor,
        int score,
        long noteCount,
        boolean covered) {
}
