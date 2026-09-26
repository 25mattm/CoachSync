package com.coachsync.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Id;
import jakarta.persistence.MappedSuperclass;
import jakarta.persistence.PrePersist;
import org.hibernate.Hibernate;

import java.time.Instant;
import java.util.UUID;

/**
 * Shared base for every CoachSync entity.
 *
 * <p>Centralizes the spec's non-standard primary-key policy in one place:
 * the {@code id} is an <em>assigned</em> {@link UUID} — never
 * {@code @GeneratedValue}/auto-increment. Records created in the iOS app arrive
 * with their own id; records created server-side receive a random UUID at
 * persist time via {@link #onPrePersist()}. Leaving {@code id} null until persist
 * keeps the common server-side {@code save()} on the efficient INSERT path
 * (a non-null assigned id makes Spring Data treat the row as an update and
 * issue a SELECT-before-INSERT — addressed in the API vertical when app import
 * lands).
 */
@MappedSuperclass
public abstract class BaseEntity {

    @Id
    private UUID id;

    /**
     * Last-modified time for app↔backend last-write-wins sync (Phase 2).
     *
     * <p><b>Client-authoritative:</b> the iOS app stamps this at its local save
     * chokepoint and sends it on every write; the server stores it verbatim and
     * ignores a write whose {@code updatedAt} is not newer than the stored value
     * (skip-stale, enforced in the write services). For rows created server-side —
     * or by a client that omits it — {@link #onPrePersist()} falls back to now.
     * Inherited by every entity.
     */
    @Column(nullable = false)
    private Instant updatedAt;

    @PrePersist
    void onPrePersist() {
        if (id == null) {
            id = UUID.randomUUID();
        }
        if (updatedAt == null) {
            updatedAt = Instant.now();
        }
    }

    public UUID getId() {
        return id;
    }

    public void setId(UUID id) {
        this.id = id;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(Instant updatedAt) {
        this.updatedAt = updatedAt;
    }

    /**
     * Identity by assigned id, proxy-safe. Using {@link Hibernate#getClass} so a
     * lazy proxy and its initialized instance compare equal. Safe with assigned
     * UUIDs because the id is stable from persist onward.
     */
    @Override
    public boolean equals(Object o) {
        if (this == o) {
            return true;
        }
        if (o == null || Hibernate.getClass(this) != Hibernate.getClass(o)) {
            return false;
        }
        BaseEntity other = (BaseEntity) o;
        return id != null && id.equals(other.id);
    }

    @Override
    public int hashCode() {
        // Constant per concrete type: stable across the persist lifecycle and
        // consistent with equals(). (Proxies resolve to the real entity class.)
        return Hibernate.getClass(this).hashCode();
    }
}
