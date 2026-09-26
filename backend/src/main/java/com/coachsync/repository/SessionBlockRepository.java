package com.coachsync.repository;

import com.coachsync.domain.SessionBlock;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Collection;
import java.util.List;
import java.util.UUID;

public interface SessionBlockRepository extends JpaRepository<SessionBlock, UUID> {

    List<SessionBlock> findBySessionIdOrderBySortOrderAsc(UUID sessionId);

    /** All blocks for a set of sessions in one query (analytics load). */
    List<SessionBlock> findBySessionIdIn(Collection<UUID> sessionIds);
}
