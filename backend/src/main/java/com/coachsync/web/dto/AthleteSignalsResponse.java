package com.coachsync.web.dto;

import java.util.UUID;

/**
 * Coach-facing insight signals for an athlete. Any field may be null when no
 * block currently triggers that signal. Mirrors the iOS InsightSignals:
 * declining / most-improved come from a per-block least-squares slope on
 * COMPLETE rep times (ordered by session date); inconsistent pacing comes from
 * the rep-to-rep coefficient of variation, averaged over recent sessions.
 * {@code ktcDecliningCount} is the athlete's KTC-assessment count when their
 * average-score trend is declining (else null).
 */
public record AthleteSignalsResponse(
        UUID athleteId,
        String decliningBlock,
        String mostImprovedBlock,
        InconsistentPacing inconsistentPacing,
        Integer ktcDecliningCount) {
}
