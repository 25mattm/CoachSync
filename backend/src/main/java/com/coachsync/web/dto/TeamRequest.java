package com.coachsync.web.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.UUID;

/** Create/update payload for a team. */
public record TeamRequest(
        UUID id,
        @NotBlank @Size(max = 255) String teamName,
        @Size(max = 255) String teamDescription,
        Boolean archived,
        Instant updatedAt) {
}
