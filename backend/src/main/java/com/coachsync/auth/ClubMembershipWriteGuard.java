package com.coachsync.auth;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpMethod;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.util.AntPathMatcher;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;
import java.util.Set;

/**
 * Closes the write hole {@link ClubTenantResolver#NO_TENANT}'s javadoc used to document as an
 * accepted tradeoff: since multi-club tenancy's slice 4 removed the sign-in allowlist, any verified
 * Apple identity can authenticate and land club-less ("pending"). Reads under {@code NO_TENANT} are
 * harmless (the sentinel matches no real club), but an un-gated mutating request would land under
 * that <em>same</em> shared sentinel — reachable and mutable by any other pending stranger.
 *
 * <p>Fail-closed by construction: a club-less caller's mutating request (POST/PUT/PATCH/DELETE) is
 * rejected (403) unless it matches one of the routes a club-less caller legitimately needs — getting
 * <em>into</em> a club, or the operator managing membership, never touching a {@code @TenantId}-scoped table. An
 * approved coach (a token carrying a {@code club} claim) is never affected; the tenant filter already
 * scopes their writes correctly. Deliberately a single deny-by-default boundary rather than a
 * per-service guard repeated on all 15 tenant-scoped write paths, so a future 16th entity is covered
 * automatically instead of silently reopening the hole.
 *
 * <p>Runs after {@link ActiveCoachFilter} (so a revoked/deleted coach is already rejected before this
 * even runs) and only inspects genuine bearer-token principals — {@code @WithMockUser} test requests
 * pass straight through, same as {@code ActiveCoachFilter}. Public routes ({@code publicPaths}, the
 * exact same list {@link SecurityConfig} marks {@code permitAll()}) are skipped outright: Spring
 * Security authenticates any request carrying a valid bearer token whether or not the target route
 * actually needs it, so without this check a stray token on a public route would otherwise still
 * reach — and could be wrongly rejected by — the club-membership check below. Sharing one list
 * with {@code SecurityConfig} means a route marked public there is automatically exempt here too,
 * instead of needing a second, independently-maintained allowlist entry.
 */
public class ClubMembershipWriteGuard extends OncePerRequestFilter {

    private static final Set<String> MUTATING_METHODS = Set.of(
            HttpMethod.POST.name(), HttpMethod.PUT.name(), HttpMethod.PATCH.name(), HttpMethod.DELETE.name());

    /**
     * The only writes a club-less caller may make — bootstrap routes for getting into a club and the
     * operator's membership routes, not data. The operator belongs to no club of their own, so those
     * routes must pass here; {@link OperatorGuard} in the service refuses everyone else. Matched by
     * method <em>and</em> exact path pattern, not by prefix. {@link AntPathMatcher}'s
     * {@code *} matches exactly one path segment and never crosses {@code /}, so
     * {@code /api/coaches/*}{@code /approve} matches only {@code /api/coaches/{id}/approve} — never
     * {@code /api/coaches} (roster create) or {@code /api/coaches/{id}} (roster update/delete).
     */
    private static final List<AllowedWrite> CLUB_LESS_WRITE_ALLOWLIST = List.of(
            new AllowedWrite("POST", "/api/clubs"),
            new AllowedWrite("POST", "/api/clubs/join"),
            new AllowedWrite("POST", "/api/coaches/*/approve"),
            new AllowedWrite("POST", "/api/coaches/*/remove"));

    private record AllowedWrite(String method, String pathPattern) {}

    private final ClubTenantResolver tenant;
    private final List<String> publicPaths;
    private final AntPathMatcher pathMatcher = new AntPathMatcher();

    public ClubMembershipWriteGuard(ClubTenantResolver tenant, List<String> publicPaths) {
        this.tenant = tenant;
        this.publicPaths = publicPaths;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication instanceof JwtAuthenticationToken
                && MUTATING_METHODS.contains(request.getMethod())
                && !matchesAny(publicPaths, request)
                && tenant.currentClubId().isEmpty()
                && !matchesAllowlisted(request)) {
            response.sendError(HttpServletResponse.SC_FORBIDDEN,
                    "You must belong to a club to do this. Submit a join code and wait for approval — "
                            + "if you were already approved, sign in again to pick up your club.");
            return;
        }
        chain.doFilter(request, response);
    }

    private boolean matchesAllowlisted(HttpServletRequest request) {
        String path = path(request);
        return CLUB_LESS_WRITE_ALLOWLIST.stream()
                .anyMatch(w -> w.method().equals(request.getMethod()) && pathMatcher.match(w.pathPattern(), path));
    }

    private boolean matchesAny(List<String> patterns, HttpServletRequest request) {
        String path = path(request);
        return patterns.stream().anyMatch(p -> pathMatcher.match(p, path));
    }

    private static String path(HttpServletRequest request) {
        // getServletPath() is unreliable here: it returns "" under MockMvc's default servlet mapping
        // (no context path is configured in this app, so requestURI is already the bare API path).
        return request.getRequestURI().substring(request.getContextPath().length());
    }
}
