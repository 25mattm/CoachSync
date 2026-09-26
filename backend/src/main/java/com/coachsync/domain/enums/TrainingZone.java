package com.coachsync.domain.enums;

/**
 * Training intensity zone for a session block. RECOVERY km is excluded from
 * training-load calculations (load/LTAD logic, a later vertical).
 */
public enum TrainingZone {
    GA_1,
    GA_2,
    E_1,
    E_2,
    AN_MIX,
    ALACTIC,
    RECOVERY
}
