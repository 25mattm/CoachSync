package com.coachsync.analytics;

import java.time.Clock;
import java.time.LocalDate;

/**
 * Pure season-year, age-category, and LTAD-target logic — the backend port of
 * the iOS {@code SeasonContext}. The single source of truth for: the season is
 * the <em>current calendar year</em> (age = season year − birth year), the
 * U10–U18 / Senior / N-A bands, and the CKC yearly km targets per category.
 *
 * <p>Stateless and side-effect-free, so it unit-tests without Spring. Callers
 * pass the season year explicitly (compute the default via {@link #currentYear};
 * never cache it — it goes stale on Jan 1).
 */
public final class SeasonContext {

    private SeasonContext() {
    }

    /**
     * Annualised growth velocity (cm/year) at/above which an athlete is flagged as
     * being in peak height velocity — coaches reduce training intensity around this
     * to protect joints and bones during rapid growth.
     */
    public static final double PHV_VELOCITY_THRESHOLD_CM_PER_YEAR = 6.0;

    /** The current season year. Pass a fixed {@link Clock} for deterministic tests. */
    public static int currentYear(Clock clock) {
        return LocalDate.now(clock).getYear();
    }

    /** Age an athlete reaches during {@code seasonYear} (birth year subtracted). */
    public static int athleteAge(LocalDate dateOfBirth, int seasonYear) {
        return seasonYear - dateOfBirth.getYear();
    }

    /**
     * Competitive age category for the season — mirrors the app exactly: under-5
     * is "N/A", 5–10 U10, then U12/U14/U16/U18 by upper bound, 19+ Senior.
     */
    public static String ageCategory(LocalDate dateOfBirth, int seasonYear) {
        int age = athleteAge(dateOfBirth, seasonYear);
        if (age < 5) {
            return "N/A";
        }
        if (age <= 10) {
            return "U10";
        }
        if (age <= 12) {
            return "U12";
        }
        if (age <= 14) {
            return "U14";
        }
        if (age <= 16) {
            return "U16";
        }
        if (age <= 18) {
            return "U18";
        }
        return "Senior";
    }

    /** True when {@code date} falls in the given season (same calendar year). */
    public static boolean inSeason(LocalDate date, int seasonYear) {
        return date.getYear() == seasonYear;
    }

    /**
     * CKC Long-Term Athlete Development yearly km target range for an age
     * category. Unrecognised categories fall through to the Senior range.
     */
    public static LtadTarget ltadKmTarget(String ageCategory) {
        return switch (ageCategory) {
            case "U10" -> new LtadTarget(200, 300);
            case "U12" -> new LtadTarget(300, 700);
            case "U14" -> new LtadTarget(700, 1530);
            case "U16" -> new LtadTarget(2000, 3500);
            case "U18" -> new LtadTarget(3600, 4000);
            default -> new LtadTarget(3600, 4000);
        };
    }

    /** A yearly km training-load target range (inclusive bounds), in kilometres. */
    public record LtadTarget(double minKm, double maxKm) {
    }
}
