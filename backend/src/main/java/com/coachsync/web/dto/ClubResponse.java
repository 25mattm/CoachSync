package com.coachsync.web.dto;

import com.coachsync.domain.Club;

import java.time.Instant;
import java.util.UUID;

/** Club representation returned by the API. {@code joinCode} is only ever surfaced to the operator. */
public record ClubResponse(UUID id, String name, String joinCode, Instant createdAt) {

    public static ClubResponse from(Club c) {
        return new ClubResponse(c.getId(), c.getName(), c.getJoinCode(), c.getCreatedAt());
    }
}
