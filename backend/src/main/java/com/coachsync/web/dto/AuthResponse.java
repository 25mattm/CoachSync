package com.coachsync.web.dto;

import java.time.Instant;
import java.util.UUID;

/**
 * Result of a sign-in: the backend session token (Bearer), the signed-in coach, and their club —
 * {@code null} while pending approval (see the multi-club tenancy plan's slice 4/5 boundary).
 * {@code clubId} lives here rather than on {@link CoachResponse}: that DTO is pinned by
 * {@code WireContractTest} against the app's general-purpose synced {@code CoachDTO} and must not
 * grow fields for a sign-in-only concern.
 */
public record AuthResponse(String token, Instant expiresAt, CoachResponse coach, UUID clubId) {
}
