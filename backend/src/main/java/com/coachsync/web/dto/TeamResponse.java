package com.coachsync.web.dto;

import com.coachsync.domain.Team;

import java.time.Instant;
import java.util.UUID;

/** Team representation returned by the API. */
public record TeamResponse(
        UUID id,
        String teamName,
        String teamDescription,
        boolean archived,
        Instant createdAt,
        Instant updatedAt) {

    public static TeamResponse from(Team t) {
        return new TeamResponse(
                t.getId(), t.getTeamName(), t.getTeamDescription(), t.isArchived(),
                t.getCreatedAt(), t.getUpdatedAt());
    }
}
