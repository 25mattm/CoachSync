package com.coachsync.repository;

import com.coachsync.domain.Athlete;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface AthleteRepository extends JpaRepository<Athlete, UUID> {

    Page<Athlete> findByIsActive(boolean active, Pageable pageable);
}
