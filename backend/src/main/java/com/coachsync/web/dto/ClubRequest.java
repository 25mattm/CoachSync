package com.coachsync.web.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/** Create payload for a club. Operator-only ({@code POST /api/clubs}). */
public record ClubRequest(@NotBlank @Size(max = 255) String name) {
}
