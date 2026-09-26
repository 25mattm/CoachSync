package com.coachsync.auth;

/**
 * Verifies an Apple Sign-in identity token and returns its identity. This interface is
 * the seam that keeps Apple's network/JWKS dependency out of tests, which stub it.
 */
public interface AppleTokenVerifier {

    /**
     * @return the verified {@link AppleIdentity}.
     * @throws com.coachsync.service.UnauthorizedException if the token fails signature,
     *         issuer, audience, or expiry validation.
     */
    AppleIdentity verify(String identityToken);
}
