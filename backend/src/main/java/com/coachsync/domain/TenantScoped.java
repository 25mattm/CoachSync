package com.coachsync.domain;

import jakarta.persistence.Column;
import jakarta.persistence.MappedSuperclass;
import org.hibernate.annotations.TenantId;

import java.util.UUID;

/**
 * Base class for every entity that belongs to exactly one club.
 *
 * <p>The {@code clubId} discriminator is what isolates one club's minor athletes' PII from another's.
 * It is deliberately <em>not</em> on {@link BaseEntity}: {@link Coach} and {@link Club} must stay
 * un-tenanted, because {@code AuthService} resolves a coach by {@code appleUserId} at sign-in and
 * {@code ActiveCoachFilter} resolves one by id on every request — both before any club is known. A
 * tenant-filtered {@code Coach} could not find its own account.
 *
 * <p>Three properties of Hibernate's {@code @TenantId}, read out of hibernate-core-7.4.1 sources
 * rather than the (silent) javadoc, are what make this a real boundary:
 * <ul>
 *   <li>The field is set automatically on persist from the session's tenant identifier and
 *       "may not be directly set by the application program" — a client can never forge a club.</li>
 *   <li>{@code TenantIdBinder} registers its {@code _tenantId} filter with
 *       {@code applyToLoadByKey = true}, so the restriction applies to <em>load-by-primary-key</em>.
 *       Ordinary {@code @Filter}s do not, and every {@code GET/PUT/DELETE /api/{thing}/{id}} depends
 *       on it: another club's id simply does not resolve.</li>
 *   <li>Opening a session with a {@code null} tenant identifier throws, so the resolver must always
 *       return a value — see {@code ClubTenantResolver.NO_TENANT}.</li>
 * </ul>
 *
 * <p>{@code clubId} is a plain discriminator column and must never become part of a primary key:
 * {@code id} stays the sole global PK, so the sync engine's natural-key merges (attendance by
 * session+athlete, performance by block+athlete+rep) and {@link BaseEntity#equals} are untouched.
 */
@MappedSuperclass
public abstract class TenantScoped extends BaseEntity {

    @TenantId
    @Column(name = "club_id", nullable = false, updatable = false)
    private UUID clubId;

    /** Read-only: Hibernate assigns this on persist. There is deliberately no setter. */
    public UUID getClubId() {
        return clubId;
    }
}
