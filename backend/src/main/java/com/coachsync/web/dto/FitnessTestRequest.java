package com.coachsync.web.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/** Create/update payload for a fitness-test result. {@code unit} defaults to "seconds". */
public record FitnessTestRequest(
        UUID id,
        @NotBlank @Size(max = 255) String testType,
        @PositiveOrZero double result,
        @Size(max = 255) String unit,
        @NotNull LocalDate testDate,
        String notes,
        Instant updatedAt) {
}
