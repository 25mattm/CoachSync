package com.coachsync.web.dto;

import jakarta.validation.constraints.NotBlank;

import java.time.Instant;
import java.util.UUID;

/**
 * Updates a note's text and optional block anchor (athlete, session, and the original
 * "logged by" coach are fixed).
 */
public record NoteUpdateRequest(
        @NotBlank String noteText,
        UUID sessionBlockId,
        Instant updatedAt) {
}
