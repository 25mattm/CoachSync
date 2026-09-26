package com.coachsync.web.dto;

import com.coachsync.domain.HeightRecord;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/** A height measurement. */
public record HeightRecordResponse(
        UUID id,
        UUID athleteId,
        double heightCm,
        LocalDate date,
        Instant createdAt,
        Instant updatedAt) {

    public static HeightRecordResponse from(HeightRecord h) {
        return new HeightRecordResponse(
                h.getId(), h.getAthlete().getId(), h.getHeightCm(), h.getDate(),
                h.getCreatedAt(), h.getUpdatedAt());
    }
}
