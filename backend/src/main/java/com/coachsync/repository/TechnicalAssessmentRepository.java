package com.coachsync.repository;

import com.coachsync.domain.TechnicalAssessment;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface TechnicalAssessmentRepository extends JpaRepository<TechnicalAssessment, UUID> {

    List<TechnicalAssessment> findByAthleteId(UUID athleteId);

    /** Athlete deletion guard — an assessment is recorded history. */
    boolean existsByAthleteId(UUID athleteId);
}
