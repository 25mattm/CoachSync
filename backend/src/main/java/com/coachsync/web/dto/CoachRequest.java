package com.coachsync.web.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.UUID;

/** Create/update payload for a coach. Only {@code name} is required. */
public record CoachRequest(
        UUID id,
        @NotBlank @Size(max = 255) String name,
        @Size(max = 255) String role,
        @Size(max = 255) String nccpLevel,
        @Size(max = 255) String colorHex,
        Instant updatedAt) {
}
