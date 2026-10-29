package com.coachsync.domain;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/**
 * A squad/team. On team delete, memberships are cascaded but
 * <strong>sessions are retained</strong> (their {@code team} FK is nulled) —
 * see {@link #sessions}.
 */
@Entity
@Table(name = "team")
public class Team extends TenantScoped {

    @Column(nullable = false)
    private String teamName;

    private String teamDescription;

    private boolean isArchived = false;

    private Instant createdAt = Timestamps.now();

    @OneToMany(mappedBy = "team", cascade = CascadeType.ALL)
    private List<TeamMembership> memberships = new ArrayList<>();

    /**
     * Sessions are RETAINED when a team is deleted — deliberately no cascade and
     * no orphanRemoval. The delete endpoint nulls {@code session.team} (the FK
     * is nullable); the rows live on for historical reporting.
     */
    @OneToMany(mappedBy = "team")
    private List<CoachSession> sessions = new ArrayList<>();

    public String getTeamName() {
        return teamName;
    }

    public void setTeamName(String teamName) {
        this.teamName = teamName;
    }

    public String getTeamDescription() {
        return teamDescription;
    }

    public void setTeamDescription(String teamDescription) {
        this.teamDescription = teamDescription;
    }

    public boolean isArchived() {
        return isArchived;
    }

    public void setArchived(boolean archived) {
        isArchived = archived;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }

    public List<TeamMembership> getMemberships() {
        return memberships;
    }

    public List<CoachSession> getSessions() {
        return sessions;
    }
}
