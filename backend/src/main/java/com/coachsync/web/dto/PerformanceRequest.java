package com.coachsync.web.dto;

import com.coachsync.domain.enums.RepEntryStatus;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;

import java.time.Instant;

/**
 * Records a rep result. A COMPLETE status requires {@code recordedTimeMs}; for
 * DNS/DNF/PENDING the time is cleared.
 */
public record PerformanceRequest(
        @PositiveOrZero Integer recordedTimeMs,
        @NotNull RepEntryStatus status,
        Instant updatedAt) {
}
