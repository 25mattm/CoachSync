package com.coachsync.web.dto;

import java.util.List;
import java.util.UUID;

/**
 * Training-load summary for a team in a season, over the team's COMPLETED
 * sessions. km totals exclude the recovery zone. {@code zoneBreakdown} lists all
 * six non-recovery zones in a fixed order (including zeros), mirroring the app's
 * team view. {@code weeklyKm} is always the last 7 days relative to today.
 */
public record TeamLoadResponse(
        UUID teamId,
        int seasonYear,
        double weeklyKm,
        double seasonalKm,
        List<ZoneKm> zoneBreakdown) {
}
