package com.coachsync.web.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/** Create/update payload for a KTC assessment. Scores are validated 1–5. */
public record KtcRequest(
        UUID id,
        @NotNull LocalDate date,
        @NotBlank @Size(max = 255) String window,
        @NotNull @Min(1) @Max(5) Integer setupRecoveryScore,
        @NotNull @Min(1) @Max(5) Integer catchScore,
        @NotNull @Min(1) @Max(5) Integer propulsionDrawScore,
        @NotNull @Min(1) @Max(5) Integer exitScore,
        String notes,
        Instant updatedAt) {
}
