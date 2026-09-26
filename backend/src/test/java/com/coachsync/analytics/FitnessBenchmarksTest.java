package com.coachsync.analytics;

import com.coachsync.domain.enums.Gender;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class FitnessBenchmarksTest {

    @Test
    void looksUpBenchmarksByGenderAgeAndTest() {
        assertEquals(31.5, FitnessBenchmarks.benchmarkSeconds(
                Gender.FEMALE, 14, FitnessBenchmarks.SPRINT_100M).getAsDouble(), 1e-9);
        assertEquals(540, FitnessBenchmarks.benchmarkSeconds(
                Gender.MALE, 16, FitnessBenchmarks.TIME_TRIAL_2000M).getAsDouble(), 1e-9); // 9:00
        assertEquals(290, FitnessBenchmarks.benchmarkSeconds(
                Gender.MALE, 17, FitnessBenchmarks.RUN_1500M).getAsDouble(), 1e-9);        // 4:50
    }

    @Test
    void emptyForOutOfRangeAgeOrUnbenchmarkedTest() {
        assertTrue(FitnessBenchmarks.benchmarkSeconds(
                Gender.FEMALE, 10, FitnessBenchmarks.SPRINT_100M).isEmpty());     // age < 11
        assertTrue(FitnessBenchmarks.benchmarkSeconds(
                Gender.MALE, 15, FitnessBenchmarks.RUN_1500M).isEmpty());         // 1500m only 16+
        assertTrue(FitnessBenchmarks.benchmarkSeconds(
                Gender.FEMALE, 14, "Pull-ups").isEmpty());                        // not benchmarked
    }

    @Test
    void emptyWithoutGender() {
        assertTrue(FitnessBenchmarks.benchmarkSeconds(null, 14, FitnessBenchmarks.SPRINT_100M).isEmpty());
    }
}
