package com.coachsync.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

import java.time.Instant;

/**
 * A coach. Replaces the app's free-text {@code createdByCoachName} stamp — sessions
 * and notes reference a Coach row.
 *
 * <p>Auth identity attaches here: {@code appleUserId} is the Apple {@code sub} of the
 * coach's Apple ID, set on first Sign in with Apple. It is unique but nullable so
 * coaches created another way (e.g. via {@code POST /api/coaches}) keep a null — MySQL
 * permits multiple NULLs under a UNIQUE index.
 */
@Entity
@Table(name = "coach")
public class Coach extends BaseEntity {

    @Column(nullable = false)
    private String name;

    private String role;

    private String nccpLevel;

    private String colorHex;

    @Column(name = "apple_user_id", unique = true)
    private String appleUserId;

    private String email;

    /**
     * The club this coach has been approved into, or {@code null} while awaiting approval.
     *
     * <p>Coach is deliberately <b>not</b> {@code TenantScoped} — it cannot be, because
     * {@code AuthService} resolves a coach by {@code appleUserId} at sign-in and
     * {@code ActiveCoachFilter} resolves one by id on every request, both before any club is known.
     * The club is therefore an ordinary association, and {@code GET /api/coaches} must be scoped by
     * hand rather than by Hibernate's tenant filter.
     *
     * <p>A nullable single-club FK: a coach signs in, lands pending with no club (and so no data
     * access), and an admin approves them. Supporting a coach in several clubs later means a
     * membership table plus an "active club" selection — the JWT claim is already named for the
     * active club, so that change is additive.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "club_id")
    private Club club;

    /**
     * The club this coach has asked to join via {@code POST /api/clubs/join}, or {@code null}. An
     * operator approving the coach copies this into {@link #club} and clears it; submitting a join
     * code never grants access on its own.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "requested_club_id")
    private Club requestedClub;

    private Instant createdAt = Timestamps.now();

    /**
     * When this coach deleted their account, or {@code null}. Marks an anonymized row kept for club
     * history. {@code appleUserId} can't serve as the marker: roster-only coaches never have one.
     */
    private Instant deletedAt;

    public Instant getDeletedAt() {
        return deletedAt;
    }

    public void setDeletedAt(Instant deletedAt) {
        this.deletedAt = deletedAt;
    }

    public Club getClub() {
        return club;
    }

    public void setClub(Club club) {
        this.club = club;
    }

    public Club getRequestedClub() {
        return requestedClub;
    }

    public void setRequestedClub(Club requestedClub) {
        this.requestedClub = requestedClub;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getAppleUserId() {
        return appleUserId;
    }

    public void setAppleUserId(String appleUserId) {
        this.appleUserId = appleUserId;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public String getRole() {
        return role;
    }

    public void setRole(String role) {
        this.role = role;
    }

    public String getNccpLevel() {
        return nccpLevel;
    }

    public void setNccpLevel(String nccpLevel) {
        this.nccpLevel = nccpLevel;
    }

    public String getColorHex() {
        return colorHex;
    }

    public void setColorHex(String colorHex) {
        this.colorHex = colorHex;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }
}
