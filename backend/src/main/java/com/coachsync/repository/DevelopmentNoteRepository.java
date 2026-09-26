package com.coachsync.repository;

import com.coachsync.domain.DevelopmentNote;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface DevelopmentNoteRepository extends JpaRepository<DevelopmentNote, UUID> {

    List<DevelopmentNote> findByAthleteId(UUID athleteId);

    /** Athlete deletion guard — a journal entry is recorded history. */
    boolean existsByAthleteId(UUID athleteId);

    /** Coach deletion guard — a journal entry attributed to the coach. */
    boolean existsByCoachId(UUID coachId);
}
