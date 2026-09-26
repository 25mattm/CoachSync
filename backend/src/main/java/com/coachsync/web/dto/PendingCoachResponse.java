package com.coachsync.web.dto;

import com.coachsync.domain.Coach;

import java.time.Instant;
import java.util.UUID;

/**
 * Operator-only view of a coach awaiting approval ({@code GET /api/coaches/pending}) — distinct from
 * {@link CoachResponse} (the app's pinned wire contract) because {@code requestedClubId} is
 * admin-tooling data the app's sync pull never needs.
 */
public record PendingCoachResponse(UUID id, String name, String email, UUID requestedClubId, Instant createdAt) {

    public static PendingCoachResponse from(Coach c) {
        return new PendingCoachResponse(c.getId(), c.getName(), c.getEmail(),
                c.getRequestedClub() != null ? c.getRequestedClub().getId() : null,
                c.getCreatedAt());
    }
}
