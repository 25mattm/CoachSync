package com.coachsync.auth;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

import java.time.Duration;
import java.util.List;

/**
 * Auth configuration, bound from {@code coachsync.auth.*}. Every field carries a
 * {@link DefaultValue} so binding never fails when a key is absent (e.g. on the test
 * classpath); real values come from {@code application.properties} (with env overrides).
 *
 * @param apple Apple Sign-in verification settings.
 * @param jwt   our own issued-token settings.
 * @param allowedEmails the <b>platform-operator</b> allowlist (see {@link OperatorGuard}) — NOT a
 *                      sign-in gate. Since the multi-club tenancy plan's slice 4, every verified
 *                      Apple identity signs in successfully ({@link AuthService} has no allowlist
 *                      check at all); this list instead gates only two operator-only actions,
 *                      {@code POST /api/clubs} and {@code POST /api/coaches/{id}/approve}. It still
 *                      FAILS CLOSED for those two actions — an empty list means no one (including
 *                      you) can create a club or approve a coach. Set via
 *                      {@code coachsync.auth.allowed-emails} / {@code COACHSYNC_ALLOWED_EMAILS}.
 */
@ConfigurationProperties("coachsync.auth")
public record AuthProperties(
        @DefaultValue Apple apple,
        @DefaultValue Jwt jwt,
        @DefaultValue List<String> allowedEmails) {

    /**
     * The committed dev-only default JWT secret. It ships in the repo (and in
     * {@code application.properties}), so it is publicly known and insecure for real use — the
     * {@code prod} profile refuses to start with it (see {@link ProdJwtSecretGuard}). Single source
     * of truth for both the binding default below and that guard's equality check.
     */
    public static final String DEV_DEFAULT_JWT_SECRET =
            "dev-only-insecure-coachsync-jwt-secret-change-me-in-production";

    /**
     * @param issuer   expected {@code iss} of Apple identity tokens.
     * @param jwksUri  Apple's public JWKS endpoint (RS256 keys).
     * @param clientIds accepted {@code aud} values — the app bundle IDs a native
     *                  Sign in with Apple token is issued for.
     */
    public record Apple(
            @DefaultValue("https://appleid.apple.com") String issuer,
            @DefaultValue("https://appleid.apple.com/auth/keys") String jwksUri,
            @DefaultValue({"com.example.CoachSync", "com.example.CoachSyncMac"})
            List<String> clientIds) {
    }

    /**
     * @param secret HMAC signing secret for HS256 (must be ≥ 32 bytes). The dev default is
     *               insecure — set {@code COACHSYNC_JWT_SECRET} in any real deployment.
     * @param issuer {@code iss} we stamp on (and require of) our own tokens.
     * @param ttl    token lifetime (Spring duration style, e.g. {@code 30d}).
     */
    public record Jwt(
            @DefaultValue(DEV_DEFAULT_JWT_SECRET)
            String secret,
            @DefaultValue("coachsync-backend") String issuer,
            @DefaultValue("30d") Duration ttl) {
    }
}
