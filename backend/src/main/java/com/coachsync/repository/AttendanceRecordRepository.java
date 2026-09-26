package com.coachsync.repository;

import com.coachsync.domain.AttendanceRecord;
import com.coachsync.domain.enums.AttendanceStatus;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface AttendanceRecordRepository extends JpaRepository<AttendanceRecord, UUID> {

    // Fetch the athlete eagerly: every caller (roster DTO mapping + reconcile)
    // reads it, so a join here avoids an N+1 over the session's attendance rows.
    @EntityGraph(attributePaths = "athlete")
    List<AttendanceRecord> findBySessionId(UUID sessionId);

    // Analytics: an athlete's rows with the given status, session fetched eagerly
    // (the load logic reads each session's status + scheduledDate).
    @EntityGraph(attributePaths = "session")
    List<AttendanceRecord> findByAthleteIdAndStatus(UUID athleteId, AttendanceStatus status);

    /** Used by the athlete deletion guard — present attendance counts as history. */
    boolean existsByAthleteIdAndStatus(UUID athleteId, AttendanceStatus status);
}
