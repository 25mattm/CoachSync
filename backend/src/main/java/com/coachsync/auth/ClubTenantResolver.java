package com.coachsync.auth;

import org.hibernate.cfg.MultiTenancySettings;
import org.hibernate.context.spi.CurrentTenantIdentifierResolver;
import org.springframework.boot.hibernate.autoconfigure.HibernatePropertiesCustomizer;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.Optional;
import java.util.UUID;

/**
 * Resolves the club (tenant) for the current request, so Hibernate can scope every
 * {@link com.coachsync.domain.TenantScoped} query and stamp every insert.
 *
 * <p>The id comes from the {@code club} claim on the caller's JWT, which
 * {@link JwtService} writes only for a coach who has been approved into a club. It is named for the
 * coach's <em>active</em> club rather than "the coach's club" so that supporting a coach in several
 * clubs later is additive: a membership table and a club switcher change where the id comes from,
 * not the shape of the token.
 *
 * <p>Two behaviours here are load-bearing, and both were verified against hibernate-core-7.4.1
 * sources rather than the documentation:
 *
 * <ol>
 *   <li><b>Never return {@code null}.</b> {@code AbstractSharedSessionContract} throws
 *       "SessionFactory configured for multi-tenancy, but no tenant identifier specified" when a
 *       session opens with a null tenant — including a session that only touches the un-tenanted
 *       {@code Coach} table. Sign-in itself would break. {@link #NO_TENANT} is therefore returned
 *       for anonymous callers and for coaches awaiting club approval; it matches no real club, so
 *       they see no rows.</li>
 *   <li><b>Never override {@code isRoot}.</b> When it returns true Hibernate <em>disables</em> the
 *       tenant filter for that session and it sees every club. The interface default is {@code false}
 *       and this class deliberately inherits it.</li>
 * </ol>
 */
@Component
public class ClubTenantResolver implements CurrentTenantIdentifierResolver<UUID>, HibernatePropertiesCustomizer {

    /**
     * The fail-closed tenant. Reserved: no real club may use it. Reads under it match no real club's
     * rows.
     *
     * <p>Writes are guarded separately, at the servlet boundary rather than per-service:
     * {@link ClubMembershipWriteGuard} rejects (403) any mutating request from a club-less
     * ("pending") caller except the three bootstrap routes that get a coach <em>into</em> a club
     * ({@code POST /api/clubs}, {@code POST /api/clubs/join}, {@code POST /api/coaches/{id}/approve}).
     * Before that guard existed, a pending coach's write would land under this sentinel — harmless to
     * any <em>real</em> club's data (it matches none), but readable and writable by any other pending
     * stranger sharing the same sentinel; multi-club tenancy's slice 4 had made this reachable by
     * removing the sign-in allowlist gate (previously only pre-vetted coaches could ever get an
     * authenticated session at all). See {@code CrossClubIsolationTest
     * .pendingCoachCannotWriteToTenantScopedEndpoints} and {@code .pendingCoachIsBlockedAcrossTheWriteSurface}
     * for the closed behavior, and {@code JoinFlowTest} for proof the three bootstrap routes still work
     * club-less.
     */
    public static final UUID NO_TENANT = new UUID(0L, 0L);

    /** The JWT claim carrying the caller's active club id. */
    public static final String CLUB_CLAIM = "club";

    @Override
    public UUID resolveCurrentTenantIdentifier() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication instanceof JwtAuthenticationToken jwt) {
            String club = jwt.getToken().getClaimAsString(CLUB_CLAIM);
            if (club != null) {
                try {
                    return UUID.fromString(club);
                } catch (IllegalArgumentException malformed) {
                    return NO_TENANT;  // a claim we can't parse is not a licence to see everything
                }
            }
        }
        // Anonymous, pending approval, or a non-request thread (startup, tests): see nothing.
        return NO_TENANT;
    }

    @Override
    public boolean validateExistingCurrentSessions() {
        return false;
    }

    /**
     * The caller's club as a genuine value, or empty when there is none (anonymous, or a coach
     * awaiting approval). Service code that must scope an <em>un-tenanted</em> table — chiefly
     * {@code Coach} — reads it here instead of duplicating the security-context parsing, so there is
     * one definition of "which club is this request". {@link #NO_TENANT} maps to empty: it is the
     * fail-closed placeholder, never a real club.
     */
    public Optional<UUID> currentClubId() {
        UUID club = resolveCurrentTenantIdentifier();
        return NO_TENANT.equals(club) ? Optional.empty() : Optional.of(club);
    }

    /**
     * The signed-in coach's id (the JWT {@code sub}), or empty for an anonymous caller / a non-request
     * thread. Unlike {@link #currentClubId()} this is available regardless of club membership — it is
     * how a request identifies <em>who</em> is calling, not which tenant to filter by. Used by
     * {@link OperatorGuard} and the club join/create flow, which must resolve the caller before any
     * club is known.
     */
    public Optional<UUID> currentCoachId() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication instanceof JwtAuthenticationToken jwt) {
            try {
                return Optional.of(UUID.fromString(jwt.getToken().getSubject()));
            } catch (IllegalArgumentException malformed) {
                return Optional.empty();
            }
        }
        return Optional.empty();
    }

    /**
     * Registers this resolver with Hibernate. Discriminator multi-tenancy needs nothing else — no
     * {@code MultiTenantConnectionProvider}, no {@code hibernate.multiTenancy} mode, and the single
     * datasource is untouched.
     */
    @Override
    public void customize(Map<String, Object> hibernateProperties) {
        hibernateProperties.put(MultiTenancySettings.MULTI_TENANT_IDENTIFIER_RESOLVER, this);
    }
}
