package com.coachsync.web.dto;

import jakarta.validation.constraints.NotNull;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/** Add-member payload. {@code joinedDate} defaults to today when omitted. */
public record TeamMembershipRequest(
        UUID id,
        @NotNull UUID athleteId,
        LocalDate joinedDate,
        LocalDate leftDate,
        Instant updatedAt) {
}
