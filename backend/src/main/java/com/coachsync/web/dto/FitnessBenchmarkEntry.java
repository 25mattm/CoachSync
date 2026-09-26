package com.coachsync.web.dto;

/**
 * An athlete's best result for a benchmarked fitness test, against the LTAD
 * benchmark. {@code percentOfBenchmark} is best / benchmark × 100 — under 100 %
 * means faster than the benchmark (these are time-based tests).
 */
public record FitnessBenchmarkEntry(
        String testType,
        double bestResultSeconds,
        double benchmarkSeconds,
        double percentOfBenchmark) {
}
