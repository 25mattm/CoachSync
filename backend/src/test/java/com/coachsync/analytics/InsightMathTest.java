package com.coachsync.analytics;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.OptionalDouble;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class InsightMathTest {

    @Test
    void slopeOfAnEvenlyRisingSeriesIsConstant() {
        assertEquals(1.0, InsightMath.leastSquaresSlope(List.of(0.0, 1.0, 2.0, 3.0)).getAsDouble(), 1e-9);
        assertEquals(100.0, InsightMath.leastSquaresSlope(List.of(100.0, 200.0, 300.0)).getAsDouble(), 1e-9);
        assertEquals(-100.0, InsightMath.leastSquaresSlope(List.of(300.0, 200.0, 100.0)).getAsDouble(), 1e-9);
    }

    @Test
    void slopeEmptyForFewerThanTwoPoints() {
        assertTrue(InsightMath.leastSquaresSlope(List.of(5.0)).isEmpty());
        assertTrue(InsightMath.leastSquaresSlope(List.of()).isEmpty());
    }

    @Test
    void coefficientOfVariationMeasuresRelativeSpread() {
        assertEquals(0.0, InsightMath.coefficientOfVariation(List.of(10.0, 10.0, 10.0)).getAsDouble(), 1e-9);
        // mean 3, population stddev 1 -> CV = 1/3
        assertEquals(1.0 / 3.0, InsightMath.coefficientOfVariation(List.of(2.0, 4.0)).getAsDouble(), 1e-9);
    }

    @Test
    void coefficientOfVariationEmptyWhenUndefined() {
        assertTrue(InsightMath.coefficientOfVariation(List.of(5.0)).isEmpty());        // < 2 points
        OptionalDouble nonPositiveMean = InsightMath.coefficientOfVariation(List.of(-1.0, 1.0));
        assertTrue(nonPositiveMean.isEmpty());                                          // mean 0
    }
}
