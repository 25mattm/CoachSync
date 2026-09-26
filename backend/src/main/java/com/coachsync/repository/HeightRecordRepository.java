package com.coachsync.repository;

import com.coachsync.domain.HeightRecord;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface HeightRecordRepository extends JpaRepository<HeightRecord, UUID> {

    List<HeightRecord> findByAthleteId(UUID athleteId);

    /** Athlete deletion guard — a height measurement is recorded history. */
    boolean existsByAthleteId(UUID athleteId);
}
