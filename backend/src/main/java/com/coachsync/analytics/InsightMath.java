package com.coachsync.analytics;

import java.util.List;
import java.util.OptionalDouble;

/**
 * Pure math primitives behind the athlete insight signals — the backend port of
 * the iOS {@code InsightSignals} helpers. Stateless, no Spring, unit-tested
 * directly.
 */
public final class InsightMath {

    private InsightMath() {
    }

    /**
     * Least-squares slope of {@code ys} against evenly spaced x values
     * (0, 1, 2, …). Empty when there are fewer than 2 points or the x-variance is
     * zero. A positive slope means the values are rising over time.
     */
    public static OptionalDouble leastSquaresSlope(List<Double> ys) {
        int n = ys.size();
        if (n < 2) {
            return OptionalDouble.empty();
        }
        double meanX = (n - 1) / 2.0;
        double meanY = ys.stream().mapToDouble(Double::doubleValue).sum() / n;
        double num = 0.0;
        double den = 0.0;
        for (int i = 0; i < n; i++) {
            double dx = i - meanX;
            num += dx * (ys.get(i) - meanY);
            den += dx * dx;
        }
        return den == 0 ? OptionalDouble.empty() : OptionalDouble.of(num / den);
    }

    /**
     * Coefficient of variation (population stddev / mean) for the samples. Empty
     * for fewer than 2 points or when the mean is zero or negative (CV is
     * undefined / meaningless there).
     */
    public static OptionalDouble coefficientOfVariation(List<Double> values) {
        int n = values.size();
        if (n < 2) {
            return OptionalDouble.empty();
        }
        double mean = values.stream().mapToDouble(Double::doubleValue).sum() / n;
        if (mean <= 0) {
            return OptionalDouble.empty();
        }
        double variance = 0.0;
        for (double v : values) {
            variance += (v - mean) * (v - mean);
        }
        variance /= n;
        return OptionalDouble.of(Math.sqrt(variance) / mean);
    }
}
