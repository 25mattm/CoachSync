package com.coachsync.repository;

import com.coachsync.domain.FitnessTestResult;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface FitnessTestResultRepository extends JpaRepository<FitnessTestResult, UUID> {

    List<FitnessTestResult> findByAthleteId(UUID athleteId);

    /** Athlete deletion guard — a fitness-test result is recorded history. */
    boolean existsByAthleteId(UUID athleteId);
}
