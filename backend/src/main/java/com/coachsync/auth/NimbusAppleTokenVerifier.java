package com.coachsync.auth;

import com.coachsync.service.UnauthorizedException;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jose.jws.SignatureAlgorithm;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.JwtIssuerValidator;
import org.springframework.security.oauth2.jwt.JwtTimestampValidator;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * Production {@link AppleTokenVerifier}: validates the token against Apple's JWKS
 * (RS256), requiring the configured issuer, a valid timestamp, and one of the configured
 * audiences (the app bundle IDs). The JWKS is fetched lazily on the first decode, so
 * constructing this bean performs no network I/O.
 */
@Component
public class NimbusAppleTokenVerifier implements AppleTokenVerifier {

    private final NimbusJwtDecoder decoder;

    public NimbusAppleTokenVerifier(AuthProperties props) {
        this.decoder = NimbusJwtDecoder.withJwkSetUri(props.apple().jwksUri())
                .jwsAlgorithm(SignatureAlgorithm.RS256)
                .build();
        this.decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(
                new JwtTimestampValidator(),
                new JwtIssuerValidator(props.apple().issuer()),
                audienceValidator(props.apple().clientIds())));
    }

    @Override
    public AppleIdentity verify(String identityToken) {
        try {
            Jwt jwt = decoder.decode(identityToken);
            return new AppleIdentity(jwt.getSubject(), jwt.getClaimAsString("email"));
        } catch (JwtException ex) {
            throw new UnauthorizedException("Apple identity token could not be verified.", ex);
        }
    }

    /** Passes when the token's {@code aud} contains one of our app bundle IDs. */
    private static OAuth2TokenValidator<Jwt> audienceValidator(List<String> clientIds) {
        return jwt -> jwt.getAudience() != null && jwt.getAudience().stream().anyMatch(clientIds::contains)
                ? OAuth2TokenValidatorResult.success()
                : OAuth2TokenValidatorResult.failure(
                        new OAuth2Error("invalid_token", "Required audience is missing.", null));
    }
}
