package com.coachsync.repository;

import com.coachsync.domain.Team;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface TeamRepository extends JpaRepository<Team, UUID> {

    Page<Team> findByIsArchived(boolean archived, Pageable pageable);
}
