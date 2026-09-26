package com.coachsync.web.dto;

import com.coachsync.domain.RegattaResult;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/** A regatta result. {@code resultTimeMs} is raw ms — the client formats it. */
public record RegattaResultResponse(
        UUID id,
        UUID athleteId,
        String regattaName,
        String location,
        LocalDate regattaDate,
        int eventDistanceMetres,
        Integer placement,
        Integer totalCompetitors,
        int resultTimeMs,
        String notes,
        Instant createdAt,
        Instant updatedAt) {

    public static RegattaResultResponse from(RegattaResult r) {
        return new RegattaResultResponse(
                r.getId(), r.getAthlete().getId(), r.getRegattaName(), r.getLocation(),
                r.getRegattaDate(), r.getEventDistanceMetres(), r.getPlacement(),
                r.getTotalCompetitors(), r.getResultTimeMs(), r.getNotes(),
                r.getCreatedAt(), r.getUpdatedAt());
    }
}
