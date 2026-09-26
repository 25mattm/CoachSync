package com.coachsync.repository;

import com.coachsync.domain.AthleteNote;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface AthleteNoteRepository extends JpaRepository<AthleteNote, UUID> {

    // Note-list finders fetch the athlete eagerly (the DTO reads athlete names);
    // session/block/coach are read as ids only, so they stay lazy.
    @EntityGraph(attributePaths = "athlete")
    List<AthleteNote> findByAthleteId(UUID athleteId);

    @EntityGraph(attributePaths = "athlete")
    List<AthleteNote> findBySessionId(UUID sessionId);

    /** Used by the athlete deletion guard — any note counts as history. */
    boolean existsByAthleteId(UUID athleteId);

    /** Coach deletion guard. */
    boolean existsByCoachId(UUID coachId);

    /** Block deletion nullifies these anchors so the notes (history) survive. */
    List<AthleteNote> findBySessionBlockId(UUID sessionBlockId);
}
