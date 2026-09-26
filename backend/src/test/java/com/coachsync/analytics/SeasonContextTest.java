package com.coachsync.analytics;

import com.coachsync.analytics.SeasonContext.LtadTarget;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SeasonContextTest {

    @Test
    void currentYearReadsTheClock() {
        Clock clock = Clock.fixed(Instant.parse("2026-06-15T12:00:00Z"), ZoneOffset.UTC);
        assertEquals(2026, SeasonContext.currentYear(clock));
    }

    @Test
    void athleteAgeIsACalendarYearSubtraction() {
        assertEquals(14, SeasonContext.athleteAge(LocalDate.of(2012, 11, 30), 2026));
        // Birth month/day are irrelevant — age category uses the season year only.
        assertEquals(14, SeasonContext.athleteAge(LocalDate.of(2012, 1, 1), 2026));
    }

    @Test
    void ageCategoryMatchesTheBands() {
        // age = 2026 - birthYear
        assertEquals("N/A", SeasonContext.ageCategory(LocalDate.of(2022, 1, 1), 2026));    // 4
        assertEquals("U10", SeasonContext.ageCategory(LocalDate.of(2021, 1, 1), 2026));    // 5
        assertEquals("U10", SeasonContext.ageCategory(LocalDate.of(2016, 1, 1), 2026));    // 10
        assertEquals("U12", SeasonContext.ageCategory(LocalDate.of(2015, 1, 1), 2026));    // 11
        assertEquals("U12", SeasonContext.ageCategory(LocalDate.of(2014, 1, 1), 2026));    // 12
        assertEquals("U14", SeasonContext.ageCategory(LocalDate.of(2013, 1, 1), 2026));    // 13
        assertEquals("U14", SeasonContext.ageCategory(LocalDate.of(2012, 1, 1), 2026));    // 14
        assertEquals("U16", SeasonContext.ageCategory(LocalDate.of(2011, 1, 1), 2026));    // 15
        assertEquals("U16", SeasonContext.ageCategory(LocalDate.of(2010, 1, 1), 2026));    // 16
        assertEquals("U18", SeasonContext.ageCategory(LocalDate.of(2009, 1, 1), 2026));    // 17
        assertEquals("U18", SeasonContext.ageCategory(LocalDate.of(2008, 1, 1), 2026));    // 18
        assertEquals("Senior", SeasonContext.ageCategory(LocalDate.of(2007, 1, 1), 2026)); // 19
    }

    @Test
    void inSeasonChecksTheCalendarYear() {
        assertTrue(SeasonContext.inSeason(LocalDate.of(2026, 1, 1), 2026));
        assertTrue(SeasonContext.inSeason(LocalDate.of(2026, 12, 31), 2026));
        assertFalse(SeasonContext.inSeason(LocalDate.of(2025, 12, 31), 2026));
        assertFalse(SeasonContext.inSeason(LocalDate.of(2027, 1, 1), 2026));
    }

    @Test
    void ltadTargetsByCategoryWithSeniorFallback() {
        assertEquals(new LtadTarget(200, 300), SeasonContext.ltadKmTarget("U10"));
        assertEquals(new LtadTarget(300, 700), SeasonContext.ltadKmTarget("U12"));
        assertEquals(new LtadTarget(700, 1530), SeasonContext.ltadKmTarget("U14"));
        assertEquals(new LtadTarget(2000, 3500), SeasonContext.ltadKmTarget("U16"));
        assertEquals(new LtadTarget(3600, 4000), SeasonContext.ltadKmTarget("U18"));
        assertEquals(new LtadTarget(3600, 4000), SeasonContext.ltadKmTarget("Senior"));
        // Unknown / N/A falls through to the Senior range.
        assertEquals(new LtadTarget(3600, 4000), SeasonContext.ltadKmTarget("N/A"));
    }
}
