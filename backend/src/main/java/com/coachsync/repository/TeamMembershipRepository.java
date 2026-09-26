package com.coachsync.repository;

import com.coachsync.domain.TeamMembership;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface TeamMembershipRepository extends JpaRepository<TeamMembership, UUID> {

    // Roster finders fetch the athlete eagerly — the roster DTO reads athlete
    // names, so a join avoids an N+1 over the team's memberships.
    @EntityGraph(attributePaths = "athlete")
    List<TeamMembership> findByTeamId(UUID teamId);

    List<TeamMembership> findByAthleteId(UUID athleteId);

    /** Currently-active memberships of a team (leftDate is null). */
    @EntityGraph(attributePaths = "athlete")
    List<TeamMembership> findByTeamIdAndLeftDateIsNull(UUID teamId);

    /** Guards against adding a duplicate active membership when joining a team. */
    boolean existsByAthleteIdAndTeamIdAndLeftDateIsNull(UUID athleteId, UUID teamId);
}
