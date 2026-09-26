package com.coachsync.analytics;

import com.coachsync.domain.HeightRecord;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class GrowthVelocityTest {

    private HeightRecord reading(LocalDate date, double cm) {
        HeightRecord h = new HeightRecord();
        h.setDate(date);
        h.setHeightCm(cm);
        return h;
    }

    @Test
    void emptyForFewerThanTwoReadings() {
        assertTrue(GrowthVelocity.cmPerYear(List.of()).isEmpty());
        assertTrue(GrowthVelocity.cmPerYear(List.of(reading(LocalDate.of(2026, 1, 1), 150))).isEmpty());
    }

    @Test
    void emptyWhenReadingsAreTooCloseTogether() {
        // ~1 month apart — under the 2-month floor.
        var records = List.of(
                reading(LocalDate.of(2026, 1, 1), 150.0),
                reading(LocalDate.of(2026, 1, 30), 151.0));
        assertTrue(GrowthVelocity.cmPerYear(records).isEmpty());
    }

    @Test
    void annualizesFromTheTwoMostRecentReadings() {
        // 365 days apart, +6 cm -> ~6 cm/year. Order shouldn't matter (helper sorts).
        var records = List.of(
                reading(LocalDate.of(2025, 6, 16), 156.0),
                reading(LocalDate.of(2024, 6, 16), 150.0),
                reading(LocalDate.of(2023, 1, 1), 140.0)); // older, ignored
        assertEquals(6.0, GrowthVelocity.cmPerYear(records).getAsDouble(), 0.05);
    }
}
