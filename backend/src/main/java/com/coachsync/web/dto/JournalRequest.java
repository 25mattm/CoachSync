package com.coachsync.web.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/**
 * Create/update payload for a development-journal entry. Full-replace (PUT):
 * {@code tags} replaces the prior set (null = none). The "logged by" author is taken
 * from the authenticated principal at create time, not this payload.
 */
public record JournalRequest(
        UUID id,
        @NotNull LocalDate date,
        @NotBlank String text,
        List<@Size(max = 255) String> tags,
        Instant updatedAt) {
}
