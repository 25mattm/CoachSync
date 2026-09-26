package com.coachsync.web.dto;

import com.coachsync.domain.Coach;

import java.time.Instant;
import java.util.UUID;

/**
 * Coach representation returned by the API. Pinned by {@code WireContractTest} against the app's
 * {@code CoachDTO} (CoachSync/Sync/SyncDTOs.swift) — do not add fields here without updating that
 * Swift struct in lockstep. Club-membership state for the approval queue is exposed separately via
 * {@link PendingCoachResponse}, not here.
 */
public record CoachResponse(
        UUID id,
        String name,
        String role,
        String nccpLevel,
        String colorHex,
        Instant createdAt,
        Instant updatedAt) {

    public static CoachResponse from(Coach c) {
        return new CoachResponse(
                c.getId(), c.getName(), c.getRole(), c.getNccpLevel(), c.getColorHex(),
                c.getCreatedAt(), c.getUpdatedAt());
    }
}
