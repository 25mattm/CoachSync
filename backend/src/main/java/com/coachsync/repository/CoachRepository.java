package com.coachsync.repository;

import com.coachsync.domain.Coach;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface CoachRepository extends JpaRepository<Coach, UUID> {

    /** Looks up the coach linked to an Apple ID ({@code sub}) on Sign in with Apple. */
    Optional<Coach> findByAppleUserId(String appleUserId);

    /**
     * Coaches in one club. {@code Coach} is un-tenanted (see {@link Coach#getClub()}), so Hibernate's
     * {@code @TenantId} filter cannot scope it — {@code CoachService} calls this to scope the roster
     * to the caller's club by hand. The {@code Club_Id} path traverses the association to its id.
     */
    Page<Coach> findByClub_Id(UUID clubId, Pageable pageable);

    /** Every coach awaiting operator approval, platform-wide — see {@code CoachService#pending}. */
    List<Coach> findByRequestedClubIsNotNull();
}
