package com.coachsync.auth;

import com.coachsync.domain.Coach;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.stereotype.Service;

import java.time.Instant;

/**
 * Issues the backend's own HS256 session tokens. The token {@code sub} is the coach id,
 * which {@code SecurityConfig}'s resource-server decoder verifies on each request.
 */
@Service
public class JwtService {

    private final JwtEncoder encoder;
    private final AuthProperties props;

    public JwtService(JwtEncoder encoder, AuthProperties props) {
        this.encoder = encoder;
        this.props = props;
    }

    public IssuedToken issue(Coach coach) {
        Instant now = Instant.now();
        Instant expiresAt = now.plus(props.jwt().ttl());
        JwtClaimsSet.Builder builder = JwtClaimsSet.builder()
                .issuer(props.jwt().issuer())
                .subject(coach.getId().toString())
                .issuedAt(now)
                .expiresAt(expiresAt)
                .claim("name", coach.getName());
        // Only an approved coach carries a club. A pending coach's token omits the claim, so
        // ClubTenantResolver falls back to NO_TENANT and they can read nothing until an admin
        // approves them — the token itself grants no data access.
        if (coach.getClub() != null) {
            builder.claim(ClubTenantResolver.CLUB_CLAIM, coach.getClub().getId().toString());
        }
        JwtClaimsSet claims = builder.build();
        String token = encoder.encode(JwtEncoderParameters.from(
                JwsHeader.with(MacAlgorithm.HS256).build(), claims)).getTokenValue();
        return new IssuedToken(token, expiresAt);
    }

    /** A freshly issued token and the instant it expires. */
    public record IssuedToken(String token, Instant expiresAt) {
    }
}
