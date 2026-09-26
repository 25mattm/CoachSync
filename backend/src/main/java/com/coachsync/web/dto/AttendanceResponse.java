package com.coachsync.web.dto;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.AttendanceRecord;
import com.coachsync.domain.enums.AttendanceStatus;

import java.time.Instant;
import java.util.UUID;

/** A session attendance row. Built inside a transaction (lazy athlete). */
public record AttendanceResponse(
        UUID id,
        UUID athleteId,
        String athleteFirstName,
        String athleteLastName,
        AttendanceStatus status,
        String absenceReason,
        Instant updatedAt) {

    public static AttendanceResponse from(AttendanceRecord r) {
        Athlete a = r.getAthlete();
        return new AttendanceResponse(
                r.getId(), a.getId(), a.getFirstName(), a.getLastName(),
                r.getStatus(), r.getAbsenceReason(), r.getUpdatedAt());
    }
}
