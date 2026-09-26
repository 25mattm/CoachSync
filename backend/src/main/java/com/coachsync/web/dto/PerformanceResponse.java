package com.coachsync.web.dto;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.PerformanceRecord;
import com.coachsync.domain.enums.RepEntryStatus;

import java.time.Instant;
import java.util.UUID;

/** A per-athlete rep slot. Built inside a transaction (lazy athlete). */
public record PerformanceResponse(
        UUID id,
        UUID athleteId,
        String athleteFirstName,
        String athleteLastName,
        int repNumber,
        Integer recordedTimeMs,
        RepEntryStatus status,
        Instant updatedAt) {

    public static PerformanceResponse from(PerformanceRecord r) {
        Athlete a = r.getAthlete();
        return new PerformanceResponse(
                r.getId(), a.getId(), a.getFirstName(), a.getLastName(),
                r.getRepNumber(), r.getRecordedTimeMs(), r.getStatus(), r.getUpdatedAt());
    }
}
