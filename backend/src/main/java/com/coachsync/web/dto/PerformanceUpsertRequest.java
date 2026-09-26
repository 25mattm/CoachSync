package com.coachsync.web.dto;

import com.coachsync.domain.enums.RepEntryStatus;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Natural-key rep-result upsert for a block (the app↔backend sync path). The iOS app and the
 * backend each generate their own rep-slot ids, so results are matched by (block, athlete, rep)
 * rather than by id. Each entry carries the client {@code updatedAt} for last-write-wins.
 */
public record PerformanceUpsertRequest(@NotEmpty @Valid List<Entry> entries) {

    public record Entry(
            @NotNull UUID athleteId,
            @NotNull Integer repNumber,
            @NotNull RepEntryStatus status,
            @PositiveOrZero Integer recordedTimeMs,
            Instant updatedAt) {
    }
}
