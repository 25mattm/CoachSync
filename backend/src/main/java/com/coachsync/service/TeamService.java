package com.coachsync.service;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.CoachSession;
import com.coachsync.domain.Team;
import com.coachsync.domain.TeamMembership;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.CoachSessionRepository;
import com.coachsync.repository.TeamMembershipRepository;
import com.coachsync.repository.TeamRepository;
import com.coachsync.web.dto.TeamMembershipRequest;
import com.coachsync.web.dto.TeamMembershipResponse;
import com.coachsync.web.dto.TeamRequest;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

@Service
public class TeamService {

    private final TeamRepository teams;
    private final CoachSessionRepository sessions;
    private final TeamMembershipRepository memberships;
    private final AthleteRepository athletes;

    public TeamService(TeamRepository teams,
                       CoachSessionRepository sessions,
                       TeamMembershipRepository memberships,
                       AthleteRepository athletes) {
        this.teams = teams;
        this.sessions = sessions;
        this.memberships = memberships;
        this.athletes = athletes;
    }

    @Transactional(readOnly = true)
    public Page<Team> list(Boolean archived, Pageable pageable) {
        return archived == null
                ? teams.findAll(pageable)
                : teams.findByIsArchived(archived, pageable);
    }

    @Transactional(readOnly = true)
    public Team get(UUID id) {
        return teams.findById(id)
                .orElseThrow(() -> new NotFoundException("No team with id " + id));
    }

    @Transactional
    public Team create(TeamRequest request) {
        if (request.id() != null) {
            var existing = teams.findById(request.id());
            if (existing.isPresent()) {
                Team managed = existing.get();
                if (SyncTimestamps.isStale(managed, request.updatedAt())) {
                    return managed;  // re-sent insert is older than the stored row — last-write-wins
                }
                // Update the stored row in place — a fresh new+save() would merge over it and reset the
                // server-owned createdAt the request never carries.
                apply(request, managed);
                return teams.save(managed);
            }
        }
        Team team = new Team();
        if (request.id() != null) {
            team.setId(request.id());
        }
        apply(request, team);
        return teams.save(team);
    }

    @Transactional
    public Team update(UUID id, TeamRequest request) {
        Team team = get(id);
        if (SyncTimestamps.isStale(team, request.updatedAt())) {
            return team;
        }
        apply(request, team);
        return teams.save(team);
    }

    @Transactional
    public Team setArchived(UUID id, boolean archived) {
        Team team = get(id);
        team.setArchived(archived);
        team.setUpdatedAt(Instant.now());
        return teams.save(team);
    }

    /**
     * Deletes a team but RETAINS its sessions: each referencing session's team is
     * nulled first (the FK is nullable), then the team is removed — which cascades
     * its memberships. Mirrors the spec's "team delete → nullify sessions".
     */
    @Transactional
    public void delete(UUID id) {
        Team team = get(id);
        List<CoachSession> teamSessions = sessions.findByTeamId(id);
        for (CoachSession session : teamSessions) {
            session.setTeam(null);
        }
        sessions.saveAll(teamSessions);
        teams.delete(team);
    }

    // --- Memberships ----------------------------------------------------------

    @Transactional(readOnly = true)
    public List<TeamMembershipResponse> roster(UUID teamId, Boolean activeOnly) {
        get(teamId); // 404 if the team does not exist
        List<TeamMembership> rows = (activeOnly != null && activeOnly)
                ? memberships.findByTeamIdAndLeftDateIsNull(teamId)
                : memberships.findByTeamId(teamId);
        return rows.stream().map(TeamMembershipResponse::from).toList();
    }

    @Transactional
    public TeamMembershipResponse addMember(UUID teamId, TeamMembershipRequest request) {
        Team team = get(teamId);
        Athlete athlete = athletes.findById(request.athleteId())
                .orElseThrow(() -> new NotFoundException("No athlete with id " + request.athleteId()));
        if (memberships.existsByAthleteIdAndTeamIdAndLeftDateIsNull(athlete.getId(), teamId)) {
            throw new ConflictException(
                    "Athlete " + athlete.getId() + " is already an active member of team " + teamId);
        }
        TeamMembership membership = new TeamMembership();
        if (request.id() != null) {
            var existing = memberships.findById(request.id());
            if (existing.isPresent() && SyncTimestamps.isStale(existing.get(), request.updatedAt())) {
                return TeamMembershipResponse.from(existing.get());  // re-sent insert is older than the stored row — last-write-wins
            }
            membership.setId(request.id());
        }
        membership.setTeam(team);
        membership.setAthlete(athlete);
        membership.setJoinedDate(request.joinedDate() != null ? request.joinedDate() : LocalDate.now());
        membership.setUpdatedAt(SyncTimestamps.resolve(request.updatedAt()));
        return TeamMembershipResponse.from(memberships.save(membership));
    }

    /**
     * Updates a membership — the sync path for a soft-leave ({@code leftDate} set) or re-join
     * ({@code leftDate} cleared). {@code leftDate} is full-replace; {@code joinedDate} is preserved
     * when omitted. Applied last-write-wins (skip-stale).
     */
    @Transactional
    public TeamMembershipResponse updateMembership(UUID teamId, UUID membershipId, TeamMembershipRequest request) {
        TeamMembership membership = memberships.findById(membershipId)
                .orElseThrow(() -> new NotFoundException("No membership with id " + membershipId));
        if (!membership.getTeam().getId().equals(teamId)) {
            throw new NotFoundException(
                    "Membership " + membershipId + " does not belong to team " + teamId);
        }
        if (SyncTimestamps.isStale(membership, request.updatedAt())) {
            return TeamMembershipResponse.from(membership);
        }
        if (request.joinedDate() != null) {
            membership.setJoinedDate(request.joinedDate());
        }
        membership.setLeftDate(request.leftDate());
        membership.setUpdatedAt(SyncTimestamps.resolve(request.updatedAt()));
        return TeamMembershipResponse.from(memberships.save(membership));
    }

    @Transactional
    public void removeMember(UUID teamId, UUID membershipId) {
        TeamMembership membership = memberships.findById(membershipId)
                .orElseThrow(() -> new NotFoundException("No membership with id " + membershipId));
        if (!membership.getTeam().getId().equals(teamId)) {
            throw new NotFoundException(
                    "Membership " + membershipId + " does not belong to team " + teamId);
        }
        memberships.delete(membership);
    }

    private void apply(TeamRequest request, Team team) {
        team.setTeamName(request.teamName());
        team.setTeamDescription(request.teamDescription());
        if (request.archived() != null) team.setArchived(request.archived());
        team.setUpdatedAt(SyncTimestamps.resolve(request.updatedAt()));
    }
}
