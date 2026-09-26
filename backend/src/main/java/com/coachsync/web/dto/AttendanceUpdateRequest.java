package com.coachsync.web.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;

import java.util.List;

/** Bulk attendance upsert for a session. */
public record AttendanceUpdateRequest(
        @NotEmpty @Valid List<AttendanceEntry> entries) {
}
