package com.coachsync.web.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.time.Instant;
import java.util.UUID;

/**
 * Creates a note under a session (the session comes from the path). The note is
 * about {@code athleteId} and optionally anchored to a block. The "logged by" coach is
 * taken from the authenticated principal, not this payload.
 */
public record NoteCreateRequest(
        UUID id,
        @NotNull UUID athleteId,
        @NotBlank String noteText,
        UUID sessionBlockId,
        Instant updatedAt) {
}
