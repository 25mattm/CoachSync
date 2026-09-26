package com.coachsync.repository;

import com.coachsync.domain.RegattaResult;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface RegattaResultRepository extends JpaRepository<RegattaResult, UUID> {

    List<RegattaResult> findByAthleteId(UUID athleteId);

    /** Athlete deletion guard — a race result is recorded history. */
    boolean existsByAthleteId(UUID athleteId);
}
