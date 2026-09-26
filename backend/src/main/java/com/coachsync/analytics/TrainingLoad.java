package com.coachsync.analytics;

import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.enums.TrainingZone;

import java.util.Collection;

/**
 * Pure training-load distance helpers — the backend port of the iOS
 * {@code SessionBlock.effectiveDistanceKm} extension and
 * {@code SeasonContext.loadKilometers}. Recovery-zone km is excluded from load
 * (a non-negotiable business rule), as is any block with no usable distance.
 */
public final class TrainingLoad {

    private TrainingLoad() {
    }

    /**
     * Best available total block distance in km: the explicit {@code distanceKm}
     * when set, else {@code repetitionCount × targetDistanceMetres / 1000}, else
     * {@code null} when the block carries no distance at all.
     */
    public static Double effectiveDistanceKm(SessionBlock block) {
        if (block.getDistanceKm() != null) {
            return block.getDistanceKm();
        }
        if (block.getTargetDistanceMetres() == null) {
            return null;
        }
        return (block.getRepetitionCount() * block.getTargetDistanceMetres()) / 1000.0;
    }

    /**
     * Sum of effective block distances in km, EXCLUDING recovery-zone blocks and
     * blocks with no distance. This is the canonical "training load" figure.
     */
    public static double loadKilometers(Collection<SessionBlock> blocks) {
        double total = 0.0;
        for (SessionBlock block : blocks) {
            if (block.getTrainingZone() == TrainingZone.RECOVERY) {
                continue;
            }
            Double km = effectiveDistanceKm(block);
            if (km != null) {
                total += km;
            }
        }
        return total;
    }
}
