package com.coachsync.analytics;

import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.HeightRecordRepository;
import com.coachsync.service.NotFoundException;
import com.coachsync.web.dto.GrowthVelocityResponse;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.OptionalDouble;
import java.util.UUID;

/**
 * Read-only PHV analytics for an athlete: annualised growth velocity from their
 * height records, and the PHV flag. Ports the iOS HeightGrowthSection.
 */
@Service
public class GrowthAnalyticsService {

    private final AthleteRepository athletes;
    private final HeightRecordRepository heights;

    public GrowthAnalyticsService(AthleteRepository athletes, HeightRecordRepository heights) {
        this.athletes = athletes;
        this.heights = heights;
    }

    @Transactional(readOnly = true)
    public GrowthVelocityResponse growthVelocity(UUID athleteId) {
        if (!athletes.existsById(athleteId)) {
            throw new NotFoundException("No athlete with id " + athleteId);
        }
        OptionalDouble velocity = GrowthVelocity.cmPerYear(heights.findByAthleteId(athleteId));
        if (velocity.isEmpty()) {
            return new GrowthVelocityResponse(athleteId, null, false);
        }
        // The PHV flag uses the raw velocity; the response value is rounded for display.
        boolean phv = velocity.getAsDouble() >= SeasonContext.PHV_VELOCITY_THRESHOLD_CM_PER_YEAR;
        return new GrowthVelocityResponse(athleteId, round1(velocity.getAsDouble()), phv);
    }

    private static double round1(double value) {
        return Math.round(value * 10.0) / 10.0;
    }
}
