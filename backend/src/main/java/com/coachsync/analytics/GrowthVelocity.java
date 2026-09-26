package com.coachsync.analytics;

import com.coachsync.domain.HeightRecord;

import java.time.temporal.ChronoUnit;
import java.util.Comparator;
import java.util.List;
import java.util.OptionalDouble;

/**
 * Pure PHV (peak height velocity) helper — the backend port of the iOS
 * {@code HeightGrowthSection.growthVelocity}. Annualised growth velocity is
 * computed from an athlete's two most recent height readings.
 */
public final class GrowthVelocity {

    private GrowthVelocity() {
    }

    /**
     * Minimum spacing (days) between the two readings for a meaningful annualised
     * velocity (~2 months). Closer than this, ordinary ±0.5 cm measurement noise
     * annualises into double-digit cm/year and fires false PHV flags.
     */
    private static final long MIN_INTERVAL_DAYS = 60;

    private static final double DAYS_PER_YEAR = 365.25;

    /**
     * Annualised growth velocity (cm/year) from the two most recent readings, or
     * empty when there are fewer than two or they are under ~2 months apart.
     */
    public static OptionalDouble cmPerYear(List<HeightRecord> records) {
        if (records.size() < 2) {
            return OptionalDouble.empty();
        }
        List<HeightRecord> sorted = records.stream()
                .sorted(Comparator.comparing(HeightRecord::getDate).reversed())
                .toList();
        HeightRecord latest = sorted.get(0);
        HeightRecord previous = sorted.get(1);
        long days = ChronoUnit.DAYS.between(previous.getDate(), latest.getDate());
        if (days < MIN_INTERVAL_DAYS) {
            return OptionalDouble.empty();
        }
        double years = days / DAYS_PER_YEAR;
        return OptionalDouble.of((latest.getHeightCm() - previous.getHeightCm()) / years);
    }
}
