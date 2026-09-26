package com.coachsync.web.dto;

import jakarta.validation.constraints.NotBlank;

/** Payload for {@code POST /api/clubs/join} — a coach registering intent to join a club. */
public record JoinClubRequest(@NotBlank String joinCode) {
}
