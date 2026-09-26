package com.coachsync.repository;

import com.coachsync.domain.CoachSession;
import com.coachsync.domain.enums.SessionStatus;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public interface CoachSessionRepository extends JpaRepository<CoachSession, UUID> {

    /** Used by the team-delete nullify path. */
    List<CoachSession> findByTeamId(UUID teamId);

    /** Coach deletion guard. */
    boolean existsByCoachId(UUID coachId);

    /** Filtered, paginated search — each filter is optional (ignored when null). */
    @Query("""
            select s from CoachSession s
            where (:status is null or s.status = :status)
              and (:teamId is null or s.team.id = :teamId)
              and (:scheduledDate is null or s.scheduledDate = :scheduledDate)
              and (:archived is null or s.isArchived = :archived)
            """)
    Page<CoachSession> search(@Param("status") SessionStatus status,
                              @Param("teamId") UUID teamId,
                              @Param("scheduledDate") LocalDate scheduledDate,
                              @Param("archived") Boolean archived,
                              Pageable pageable);
}
