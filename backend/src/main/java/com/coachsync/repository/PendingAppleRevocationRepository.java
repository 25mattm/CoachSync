package com.coachsync.repository;

import com.coachsync.domain.PendingAppleRevocation;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface PendingAppleRevocationRepository extends JpaRepository<PendingAppleRevocation, UUID> {
}
