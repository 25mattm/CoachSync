package com.coachsync.web.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/** One scored factor within an assessment create/update payload. */
public record RatingRequest(
        @NotBlank @Size(max = 255) String category,
        @NotBlank @Size(max = 255) String factor,
        @NotNull @Min(1) @Max(5) Integer score,
        @Size(max = 255) String comment) {
}
