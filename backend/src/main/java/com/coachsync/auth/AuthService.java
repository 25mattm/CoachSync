package com.coachsync.auth;

import com.coachsync.domain.Coach;
import com.coachsync.repository.CoachRepository;
import com.coachsync.web.dto.AppleSignInRequest;
import com.coachsync.web.dto.AuthResponse;
import com.coachsync.web.dto.CoachResponse;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

/**
 * Sign in with Apple: verify the Apple token, then link by Apple {@code sub} (or auto-provision) a
 * {@link Coach} and issue our own token. Every verified Apple identity signs in successfully — there
 * is no allowlist gate here any more (see the multi-club tenancy plan's settled slice 4 design).
 * A newly provisioned coach lands with {@code club == null}: no {@code club} JWT claim, so
 * {@link ClubTenantResolver} resolves the sentinel tenant and the coach reads and writes nothing
 * until a platform operator approves them into a club ({@code POST /api/coaches/{id}/approve}). The
 * {@code apple_user_id} unique constraint prevents duplicate coaches on a repeat sign-in.
 */
@Service
public class AuthService {

    private final AppleTokenVerifier verifier;
    private final CoachRepository coaches;
    private final JwtService jwtService;

    public AuthService(AppleTokenVerifier verifier, CoachRepository coaches, JwtService jwtService) {
        this.verifier = verifier;
        this.coaches = coaches;
        this.jwtService = jwtService;
    }

    @Transactional
    public AuthResponse signInWithApple(AppleSignInRequest request) {
        AppleIdentity identity = verifier.verify(request.identityToken());
        Coach coach = coaches.findByAppleUserId(identity.sub())
                .orElseGet(() -> provision(identity, request.displayName()));
        JwtService.IssuedToken issued = jwtService.issue(coach);
        UUID clubId = coach.getClub() != null ? coach.getClub().getId() : null;
        return new AuthResponse(issued.token(), issued.expiresAt(), CoachResponse.from(coach), clubId);
    }

    private Coach provision(AppleIdentity identity, String displayName) {
        Coach coach = new Coach();
        coach.setAppleUserId(identity.sub());
        coach.setEmail(identity.email());
        coach.setName(resolveName(displayName, identity.email()));
        return coaches.save(coach);
    }

    /** Apple omits the name from the token, so prefer the app-supplied display name. */
    private static String resolveName(String displayName, String email) {
        if (displayName != null && !displayName.isBlank()) {
            return displayName.trim();
        }
        if (email != null && !email.isBlank()) {
            return email.trim();
        }
        return "Coach";
    }
}
