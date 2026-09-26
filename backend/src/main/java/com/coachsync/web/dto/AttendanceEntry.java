package com.coachsync.web.dto;

import com.coachsync.domain.enums.AttendanceStatus;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.UUID;

/** One athlete's attendance in a bulk update. */
public record AttendanceEntry(
        UUID id,
        @NotNull UUID athleteId,
        @NotNull AttendanceStatus status,
        @Size(max = 255) String absenceReason,
        Instant updatedAt) {
}
