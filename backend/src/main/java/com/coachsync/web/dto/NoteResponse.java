package com.coachsync.web.dto;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.AthleteNote;

import java.time.Instant;
import java.util.UUID;

/** A development/coaching note. Built inside a transaction (lazy associations). */
public record NoteResponse(
        UUID id,
        String noteText,
        Instant createdAt,
        UUID athleteId,
        String athleteFirstName,
        String athleteLastName,
        UUID sessionId,
        UUID sessionBlockId,
        UUID coachId,
        Instant updatedAt) {

    public static NoteResponse from(AthleteNote n) {
        Athlete a = n.getAthlete();
        return new NoteResponse(
                n.getId(), n.getNoteText(), n.getCreatedAt(),
                a.getId(), a.getFirstName(), a.getLastName(),
                n.getSession().getId(),
                n.getSessionBlock() == null ? null : n.getSessionBlock().getId(),
                n.getCoach() == null ? null : n.getCoach().getId(),
                n.getUpdatedAt());
    }
}
