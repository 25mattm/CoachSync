package com.coachsync.repository;

import com.coachsync.domain.KtcAssessment;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface KtcAssessmentRepository extends JpaRepository<KtcAssessment, UUID> {

    List<KtcAssessment> findByAthleteId(UUID athleteId);

    /** Athlete deletion guard — a KTC assessment is recorded history. */
    boolean existsByAthleteId(UUID athleteId);
}
