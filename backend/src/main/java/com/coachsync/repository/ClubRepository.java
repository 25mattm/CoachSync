package com.coachsync.repository;

import com.coachsync.domain.Club;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

/**
 * {@link Club} is un-tenanted (it is the tenant), so this is an ordinary repository with no
 * discriminator filtering.
 */
public interface ClubRepository extends JpaRepository<Club, UUID> {

    /** Looks up a club by its shareable join code ({@code POST /api/clubs/join}). */
    Optional<Club> findByJoinCode(String joinCode);
}
