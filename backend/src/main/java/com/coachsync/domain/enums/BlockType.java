package com.coachsync.domain.enums;

/**
 * The nine session-block types. The iOS app stores display strings
 * ("Paddle Distance"); a future import maps those to these constants.
 */
public enum BlockType {
    PADDLE_DISTANCE,
    PADDLE_TIME_PIECES,
    PADDLE_PYRAMID,
    RUN_DISTANCE,
    RUN_INTERVALS,
    WEIGHTS,
    CIRCUIT,
    CORE,
    TECHNIQUE;

    /**
     * True for block types whose logger captures per-rep data per athlete via
     * pre-generated {@code PerformanceRecord} slots. Note-driven land blocks
     * (weights/circuit/core) and structural blocks (technique) get no slots.
     *
     * <p>Single source of truth for slot generation and reconciliation —
     * mirrors the iOS {@code BlockType.capturesPerRepData} (CoachSync/Models.swift).
     */
    public boolean capturesPerRepData() {
        return switch (this) {
            case PADDLE_DISTANCE, PADDLE_TIME_PIECES, PADDLE_PYRAMID,
                 RUN_DISTANCE, RUN_INTERVALS -> true;
            case WEIGHTS, CIRCUIT, CORE, TECHNIQUE -> false;
        };
    }
}
