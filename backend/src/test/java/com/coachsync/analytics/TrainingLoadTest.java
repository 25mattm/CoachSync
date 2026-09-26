package com.coachsync.analytics;

import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.enums.TrainingZone;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

class TrainingLoadTest {

    private SessionBlock block(Double distanceKm, Double targetMetres, int reps, TrainingZone zone) {
        SessionBlock b = new SessionBlock();
        b.setDistanceKm(distanceKm);
        b.setTargetDistanceMetres(targetMetres);
        b.setRepetitionCount(reps);
        b.setTrainingZone(zone);
        return b;
    }

    @Test
    void effectiveDistancePrefersExplicitKm() {
        assertEquals(8.0, TrainingLoad.effectiveDistanceKm(block(8.0, 200.0, 3, TrainingZone.GA_1)), 1e-9);
    }

    @Test
    void effectiveDistanceFallsBackToRepsTimesMetres() {
        // 3 × 200 m = 600 m = 0.6 km
        assertEquals(0.6, TrainingLoad.effectiveDistanceKm(block(null, 200.0, 3, TrainingZone.GA_1)), 1e-9);
    }

    @Test
    void effectiveDistanceNullWhenNoDistance() {
        assertNull(TrainingLoad.effectiveDistanceKm(block(null, null, 3, TrainingZone.GA_1)));
    }

    @Test
    void loadKilometersSumsExcludingRecoveryAndNulls() {
        double km = TrainingLoad.loadKilometers(List.of(
                block(10.0, null, 1, TrainingZone.GA_1),    // +10.0
                block(5.0, null, 1, TrainingZone.RECOVERY), // excluded (recovery zone)
                block(null, 500.0, 2, TrainingZone.E_1),    // +1.0  (2 × 500 m)
                block(null, null, 1, TrainingZone.GA_2)     // +0    (no distance)
        ));
        assertEquals(11.0, km, 1e-9);
    }
}
