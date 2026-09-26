package com.coachsync.web.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/** Create/update payload for a regatta result. */
public record RegattaResultRequest(
        UUID id,
        @NotBlank @Size(max = 255) String regattaName,
        @Size(max = 255) String location,
        @NotNull LocalDate regattaDate,
        @PositiveOrZero int eventDistanceMetres,
        @Positive Integer placement,
        @Positive Integer totalCompetitors,
        @PositiveOrZero int resultTimeMs,
        String notes,
        Instant updatedAt) {
}
