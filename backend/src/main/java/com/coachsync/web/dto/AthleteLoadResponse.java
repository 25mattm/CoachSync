package com.coachsync.web.dto;

import java.util.List;
import java.util.UUID;

/**
 * Training-load summary for one athlete in a season. All km totals exclude the
 * recovery zone; {@code seasonalPaddleKm} (on-water km only) is what the LTAD
 * progress bar measures against the age category's yearly target range.
 * {@code weeklyKm} is always the last 7 days relative to today. The zone
 * breakdown omits zones with no km.
 */
public record AthleteLoadResponse(
        UUID athleteId,
        int seasonYear,
        String ageCategory,
        double weeklyKm,
        double seasonalKm,
        double seasonalPaddleKm,
        double ltadTargetMinKm,
        double ltadTargetMaxKm,
        double ltadProgressPct,
        List<ZoneKm> zoneBreakdown) {
}
