package com.coachsync.auth;

import com.coachsync.domain.Club;
import com.coachsync.domain.Coach;
import com.coachsync.repository.CoachRepository;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.UUID;

/**
 * Per-request revocation guard. Once a bearer token has been authenticated, this confirms its
 * subject still maps to an existing, still-genuine {@link Coach} AND that the token's {@code club}
 * claim still matches that coach's <em>current</em> club — so a coach moved to another club, or
 * removed from theirs, is rejected (401) on the very next request instead of retaining access for
 * the token's full 30-day life. A token with no {@code club} claim (a coach still pending approval)
 * is always accepted here: {@link ClubTenantResolver} already resolves such a request to the
 * sentinel tenant, which grants no data regardless of the coach's actual state.
 *
 * <p><b>"Still genuine" is load-bearing, not just "a row exists at this id."</b> {@code Coach} rows
 * are hard-deleted (no tombstone) and {@code id} is a client-assignable UUID
 * ({@code POST /api/coaches} upserts by client-supplied id — see {@code CoachService#create}), so a
 * deleted coach's id can be reused by any other club member creating a new coach afterward. Without
 * an identity check tying a token to the <em>specific person</em> it was issued to (not merely "the
 * row currently at this id"), that would resurrect a revoked 30-day token — it would still find a
 * row, and that row's club could easily match the token's claim. {@code appleUserId} is the anchor:
 * it is set exactly once, at Sign in with Apple provisioning ({@code AuthService#provision}), never
 * changed afterward, and {@code POST /api/coaches}-created rows (the only other way a {@code Coach}
 * row comes to exist, including a resurrected one) never carry one ({@code CoachRequest} has no such
 * field). So a token whose coach id now resolves to a row with a null {@code appleUserId} is never a
 * legitimate holder of that token and is rejected here too.
 *
 * <p>Only real bearer-token auth is checked (the principal is a {@link JwtAuthenticationToken}),
 * so the public {@code /api/auth} + docs paths — and {@code @WithMockUser} requests in tests —
 * pass straight through.
 */
public class ActiveCoachFilter extends OncePerRequestFilter {

    private final CoachRepository coaches;

    public ActiveCoachFilter(CoachRepository coaches) {
        this.coaches = coaches;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication instanceof JwtAuthenticationToken jwtAuth && !stillValid(jwtAuth.getToken())) {
            SecurityContextHolder.clearContext();
            response.sendError(HttpServletResponse.SC_UNAUTHORIZED,
                    "The signed-in coach no longer exists or is no longer a member of this club. "
                            + "Please sign in again.");
            return;
        }
        chain.doFilter(request, response);
    }

    private boolean stillValid(Jwt jwt) {
        UUID id = parseUuid(jwt.getSubject());
        if (id == null) {
            return false;
        }
        return coaches.findById(id)
                .map(coach -> isGenuine(coach)
                        && claimMatchesCurrentClub(jwt.getClaimAsString(ClubTenantResolver.CLUB_CLAIM), coach))
                .orElse(false);
    }

    /**
     * Only a coach who actually signed in with Apple can legitimately hold a token — see the class
     * javadoc for why a null {@code appleUserId} means "not the coach this token was issued to,"
     * not just "an unusual but valid coach."
     */
    private static boolean isGenuine(Coach coach) {
        return coach.getAppleUserId() != null;
    }

    private static boolean claimMatchesCurrentClub(String claimedClub, Coach coach) {
        if (claimedClub == null) {
            // A pending-approval token: NO_TENANT already grants no data no matter what the coach's
            // actual club is, so there is nothing here to revoke.
            return true;
        }
        Club club = coach.getClub();
        return club != null && claimedClub.equals(club.getId().toString());
    }

    private static UUID parseUuid(String value) {
        if (value == null) {
            return null;
        }
        try {
            return UUID.fromString(value);
        } catch (IllegalArgumentException ex) {
            return null;
        }
    }
}
