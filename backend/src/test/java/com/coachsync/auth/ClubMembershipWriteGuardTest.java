package com.coachsync.auth;

import jakarta.servlet.FilterChain;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Pure unit coverage for the {@code publicPaths} carve-out — no real mutating route lives on a
 * public path today (see {@link SecurityConfig#PUBLIC_PATHS}), so unlike the rest of this filter's
 * behavior (proven live through MockMvc in {@code CrossClubIsolationTest}), this can't be exercised
 * through an actual route. Constructs the filter directly with mocked collaborators instead, calling
 * {@code doFilterInternal} directly (same package) to skip {@code OncePerRequestFilter}'s
 * already-filtered bookkeeping, which isn't the concern under test here.
 */
class ClubMembershipWriteGuardTest {

    @AfterEach
    void clearSecurityContext() {
        SecurityContextHolder.clearContext();
    }

    private static void authenticateAsPendingCoach() {
        Jwt jwt = Jwt.withTokenValue("test")
                .header("alg", "none")
                .subject(UUID.randomUUID().toString())
                .issuedAt(Instant.now())
                .expiresAt(Instant.now().plusSeconds(60))
                .build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt));
    }

    private static HttpServletRequest requestFor(String method, String uri) {
        HttpServletRequest request = mock(HttpServletRequest.class);
        when(request.getMethod()).thenReturn(method);
        when(request.getRequestURI()).thenReturn(uri);
        when(request.getContextPath()).thenReturn("");
        return request;
    }

    private static ClubTenantResolver clubLessResolver() {
        ClubTenantResolver tenant = mock(ClubTenantResolver.class);
        when(tenant.currentClubId()).thenReturn(Optional.empty());
        return tenant;
    }

    @Test
    void aClubLessCallersWriteToAPublicPathIsNeverBlocked() throws Exception {
        authenticateAsPendingCoach();
        ClubMembershipWriteGuard guard =
                new ClubMembershipWriteGuard(clubLessResolver(), List.of("/api/auth/**"));
        HttpServletRequest request = requestFor("POST", "/api/auth/refresh");
        HttpServletResponse response = mock(HttpServletResponse.class);
        FilterChain chain = mock(FilterChain.class);

        guard.doFilterInternal(request, response, chain);

        verify(chain).doFilter(request, response);
        verify(response, never()).sendError(any(Integer.class), any());
    }

    @Test
    void aClubLessCallersWriteToAnUnlistedPathIsStillBlocked() throws Exception {
        authenticateAsPendingCoach();
        ClubMembershipWriteGuard guard =
                new ClubMembershipWriteGuard(clubLessResolver(), List.of("/api/auth/**"));
        HttpServletRequest request = requestFor("POST", "/api/athletes");
        HttpServletResponse response = mock(HttpServletResponse.class);
        FilterChain chain = mock(FilterChain.class);

        guard.doFilterInternal(request, response, chain);

        verify(chain, never()).doFilter(any(), any());
        verify(response).sendError(eq(403), any());
    }
}
