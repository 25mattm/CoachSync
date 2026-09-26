package com.coachsync.web.dto;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.TeamMembership;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/**
 * A roster entry. Built inside a transaction (the {@code athlete}/{@code team}
 * associations are lazy).
 */
public record TeamMembershipResponse(
        UUID id,
        UUID athleteId,
        String athleteFirstName,
        String athleteLastName,
        UUID teamId,
        LocalDate joinedDate,
        LocalDate leftDate,
        Instant updatedAt) {

    public static TeamMembershipResponse from(TeamMembership m) {
        Athlete a = m.getAthlete();
        return new TeamMembershipResponse(
                m.getId(), a.getId(), a.getFirstName(), a.getLastName(),
                m.getTeam().getId(), m.getJoinedDate(), m.getLeftDate(), m.getUpdatedAt());
    }
}
