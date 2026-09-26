package com.coachsync.repository;

import com.coachsync.domain.PerformanceRecord;
import com.coachsync.domain.enums.RepEntryStatus;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface PerformanceRecordRepository extends JpaRepository<PerformanceRecord, UUID> {

    // Fetch the athlete eagerly: the performance-list DTO mapping and reconcile
    // both read it, so a join here avoids an N+1 over the block's rep slots.
    @EntityGraph(attributePaths = "athlete")
    List<PerformanceRecord> findBySessionBlockId(UUID sessionBlockId);

    // Signals: an athlete's rep results of a given status, with the block and its
    // session fetched (the slope/CV math needs block name + session date).
    @EntityGraph(attributePaths = {"sessionBlock", "sessionBlock.session"})
    List<PerformanceRecord> findByAthleteIdAndStatus(UUID athleteId, RepEntryStatus status);

    // Needs-Attention scan: every athlete's rep results of a status, with athlete
    // + block + session fetched so the whole scan is a single query.
    @EntityGraph(attributePaths = {"athlete", "sessionBlock", "sessionBlock.session"})
    List<PerformanceRecord> findByStatus(RepEntryStatus status);

    /** Mirrors the (sessionBlock, athlete, repNumber) unique constraint. */
    Optional<PerformanceRecord> findBySessionBlockIdAndAthleteIdAndRepNumber(
            UUID sessionBlockId, UUID athleteId, int repNumber);

    // Athlete deletion guard: a "filled" rep (a non-PENDING status, or a recorded
    // time) counts as history; pending no-time slots do not.
    boolean existsByAthleteIdAndStatusNot(UUID athleteId, RepEntryStatus status);

    boolean existsByAthleteIdAndRecordedTimeMsIsNotNull(UUID athleteId);
}
