package com.coachsync.web.dto;

import com.coachsync.domain.CoachSession;
import com.coachsync.domain.enums.SessionStatus;

import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.UUID;

/**
 * Session representation. {@code coachId}/{@code teamId} are read from the lazy
 * associations' ids only (no initialization), so this maps safely outside a
 * transaction.
 */
public record SessionResponse(
        UUID id,
        String sessionName,
        LocalDate scheduledDate,
        LocalDateTime startTime,
        LocalDateTime endTime,
        SessionStatus status,
        String weatherNote,
        String teamNote,
        String sessionNote,
        String mfCue,
        boolean archived,
        UUID coachId,
        UUID teamId,
        Instant createdAt,
        Instant updatedAt) {

    public static SessionResponse from(CoachSession s) {
        return new SessionResponse(
                s.getId(), s.getSessionName(), s.getScheduledDate(), s.getStartTime(), s.getEndTime(),
                s.getStatus(), s.getWeatherNote(), s.getTeamNote(), s.getSessionNote(), s.getMfCue(),
                s.isArchived(),
                s.getCoach() == null ? null : s.getCoach().getId(),
                s.getTeam() == null ? null : s.getTeam().getId(),
                s.getCreatedAt(), s.getUpdatedAt());
    }
}
