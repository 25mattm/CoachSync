package com.coachsync.web.dto;

import java.util.UUID;

/**
 * An athlete's annualised growth velocity (from the two most recent height
 * readings) and whether it crosses the PHV threshold. {@code growthVelocityCmPerYear}
 * is null when there aren't two readings far enough apart to estimate.
 */
public record GrowthVelocityResponse(
        UUID athleteId,
        Double growthVelocityCmPerYear,
        boolean phv) {
}
