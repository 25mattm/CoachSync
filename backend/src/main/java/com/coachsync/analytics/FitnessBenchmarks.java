package com.coachsync.analytics;

import com.coachsync.domain.enums.Gender;

import java.util.OptionalDouble;

/**
 * CKC LTAD fitness-test benchmark times (seconds), by gender + age, for the three
 * benchmarked tests — the backend port of the iOS {@code ltadBenchmarkSeconds}.
 * Lower is better (these are time trials/sprints). Unbenchmarked tests or
 * out-of-range ages return empty; no gender returns empty.
 */
public final class FitnessBenchmarks {

    public static final String TIME_TRIAL_2000M = "2000m Time Trial";
    public static final String SPRINT_100M = "100m Sprint";
    public static final String RUN_1500M = "1500m Run";

    private FitnessBenchmarks() {
    }

    public static OptionalDouble benchmarkSeconds(Gender gender, int age, String testType) {
        if (gender == null || testType == null) {
            return OptionalDouble.empty();
        }
        return switch (gender) {
            case FEMALE -> female(age, testType);
            case MALE -> male(age, testType);
        };
    }

    private static OptionalDouble female(int age, String testType) {
        if (TIME_TRIAL_2000M.equals(testType)) {
            return switch (age) {
                case 11, 12 -> OptionalDouble.of(15 * 60 + 30);
                case 13 -> OptionalDouble.of(14 * 60);
                case 14 -> OptionalDouble.of(12 * 60 + 30);
                case 15 -> OptionalDouble.of(11 * 60 + 45);
                case 16 -> OptionalDouble.of(11 * 60);
                case 17 -> OptionalDouble.of(10 * 60 + 50);
                case 18 -> OptionalDouble.of(10 * 60 + 15);
                default -> OptionalDouble.empty();
            };
        }
        if (SPRINT_100M.equals(testType)) {
            return switch (age) {
                case 11, 12 -> OptionalDouble.of(36);
                case 13 -> OptionalDouble.of(34);
                case 14 -> OptionalDouble.of(31.5);
                case 15 -> OptionalDouble.of(28.5);
                case 16 -> OptionalDouble.of(27.5);
                case 17 -> OptionalDouble.of(26.5);
                case 18 -> OptionalDouble.of(25.5);
                default -> OptionalDouble.empty();
            };
        }
        if (RUN_1500M.equals(testType)) {
            return age >= 16 ? OptionalDouble.of(6 * 60) : OptionalDouble.empty();
        }
        return OptionalDouble.empty();
    }

    private static OptionalDouble male(int age, String testType) {
        if (TIME_TRIAL_2000M.equals(testType)) {
            return switch (age) {
                case 11, 12 -> OptionalDouble.of(12 * 60);
                case 13 -> OptionalDouble.of(11 * 60);
                case 14 -> OptionalDouble.of(10 * 60 + 10);
                case 15 -> OptionalDouble.of(9 * 60 + 40);
                case 16 -> OptionalDouble.of(9 * 60);
                case 17 -> OptionalDouble.of(8 * 60 + 30);
                case 18 -> OptionalDouble.of(8 * 60 + 5);
                default -> OptionalDouble.empty();
            };
        }
        if (SPRINT_100M.equals(testType)) {
            return switch (age) {
                case 11, 12 -> OptionalDouble.of(30);
                case 13 -> OptionalDouble.of(28);
                case 14 -> OptionalDouble.of(26);
                case 15 -> OptionalDouble.of(23);
                case 16 -> OptionalDouble.of(21);
                case 17 -> OptionalDouble.of(20);
                case 18 -> OptionalDouble.of(19.5);
                default -> OptionalDouble.empty();
            };
        }
        if (RUN_1500M.equals(testType)) {
            return switch (age) {
                case 16 -> OptionalDouble.of(5 * 60);
                case 17 -> OptionalDouble.of(4 * 60 + 50);
                case 18 -> OptionalDouble.of(4 * 60 + 40);
                default -> OptionalDouble.empty();
            };
        }
        return OptionalDouble.empty();
    }
}
