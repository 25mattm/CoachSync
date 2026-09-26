package com.coachsync.web.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/** Create/update payload for a height measurement. */
public record HeightRecordRequest(
        UUID id,
        @Positive double heightCm,
        @NotNull LocalDate date,
        Instant updatedAt) {
}
