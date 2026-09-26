package com.coachsync.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.Locale;
import java.util.UUID;

/**
 * A paddling club — the tenant. Every {@link TenantScoped} row belongs to exactly one.
 *
 * <p>Un-tenanted on purpose (extends {@link BaseEntity}, not {@link TenantScoped}): a club cannot
 * be scoped to itself, and it must be resolvable while a coach is still deciding which club to join.
 */
@Entity
@Table(name = "club")
public class Club extends BaseEntity {

    @Column(nullable = false)
    private String name;

    /**
     * Shareable code a coach submits to {@code POST /api/clubs/join} to request membership. The code
     * routes intent only — it never grants access by itself; an operator still approves the coach
     * (see {@link Coach#getRequestedClub()}).
     *
     * <p>Defaulted here (mirrors {@link #createdAt}) so any direct {@code new Club()} — chiefly test
     * fixtures — satisfies the NOT NULL/unique constraint without every caller needing to think about
     * it. {@code ClubService#create} always overwrites this with the real, collision-checked,
     * human-typable code; this default is never a live join code in production.
     */
    @Column(name = "join_code", nullable = false, unique = true)
    private String joinCode = UUID.randomUUID().toString().substring(0, 8).toUpperCase(Locale.ROOT);

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getJoinCode() {
        return joinCode;
    }

    public void setJoinCode(String joinCode) {
        this.joinCode = joinCode;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }
}
