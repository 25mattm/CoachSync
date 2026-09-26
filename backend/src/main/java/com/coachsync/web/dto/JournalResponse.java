package com.coachsync.web.dto;

import com.coachsync.domain.DevelopmentNote;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/** A development-journal entry. Built inside a transaction (lazy tags/coach). */
public record JournalResponse(
        UUID id,
        UUID athleteId,
        LocalDate date,
        String text,
        List<String> tags,
        UUID coachId,
        Instant createdAt,
        Instant updatedAt) {

    public static JournalResponse from(DevelopmentNote n) {
        return new JournalResponse(
                n.getId(), n.getAthlete().getId(), n.getDate(), n.getText(),
                List.copyOf(n.getTags()),
                n.getCoach() == null ? null : n.getCoach().getId(),
                n.getCreatedAt(), n.getUpdatedAt());
    }
}
