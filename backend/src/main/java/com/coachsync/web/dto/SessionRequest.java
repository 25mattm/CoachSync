package com.coachsync.web.dto;

import com.coachsync.domain.enums.SessionStatus;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.UUID;

/**
 * Create/update payload for a session. Full-replace (PUT) for the profile fields;
 * {@code status} and {@code archived} are managed via their own PATCH endpoints. The
 * "logged by" coach is taken from the authenticated principal at create time (not this
 * payload, and not changed on update); {@code teamId} is an optional reference (resolved
 * to 404 if it doesn't exist). {@code sessionNote} is long free text (no length cap).
 */
public record SessionRequest(
        UUID id,
        @NotBlank @Size(max = 255) String sessionName,
        @NotNull LocalDate scheduledDate,
        LocalDateTime startTime,
        LocalDateTime endTime,
        @Size(max = 255) String weatherNote,
        @Size(max = 255) String teamNote,
        String sessionNote,
        @Size(max = 255) String mfCue,
        UUID teamId,
        SessionStatus status,
        Boolean archived,
        Instant updatedAt) {
}
