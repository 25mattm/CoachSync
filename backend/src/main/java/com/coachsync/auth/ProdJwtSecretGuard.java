package com.coachsync.auth;

import jakarta.annotation.PostConstruct;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;

/**
 * Fail-fast: refuses to start the {@code prod} profile with an insecure JWT signing secret.
 *
 * <p>The inline default in {@code application.properties} is committed and therefore publicly
 * known; booting production with it — or with any secret shorter than the 32 bytes HS256 needs —
 * would let anyone forge a Bearer token for any coach and reach every minor athlete's PII. This
 * guard only runs under {@code prod} (the Dockerfile sets {@code SPRING_PROFILES_ACTIVE=prod}), so
 * dev and tests keep the convenient default. It enforces in code what DEPLOY.md only documents: a
 * real {@code COACHSYNC_JWT_SECRET} must be set.
 */
@Component
@Profile("prod")
public class ProdJwtSecretGuard {

    /** HS256 needs a key of at least 256 bits. */
    private static final int MIN_SECRET_BYTES = 32;

    private final AuthProperties properties;

    public ProdJwtSecretGuard(AuthProperties properties) {
        this.properties = properties;
    }

    @PostConstruct
    void verifySecretIsProductionGrade() {
        validateSecret(properties.jwt().secret());
    }

    /**
     * Throws {@link IllegalStateException} — aborting startup — when the secret is missing, is still
     * the committed dev default, or is too short for HS256. Package-private and static so it can be
     * unit-tested in isolation as well as via context startup.
     */
    static void validateSecret(String secret) {
        if (secret == null || secret.isBlank()) {
            throw new IllegalStateException(
                    "coachsync.auth.jwt.secret is not set. Set COACHSYNC_JWT_SECRET (>= "
                            + MIN_SECRET_BYTES + " bytes) before starting the prod profile.");
        }
        if (secret.equals(AuthProperties.DEV_DEFAULT_JWT_SECRET)) {
            throw new IllegalStateException(
                    "coachsync.auth.jwt.secret is still the committed dev default, which is publicly "
                            + "known and lets anyone forge tokens. Set COACHSYNC_JWT_SECRET to a private "
                            + "value of at least " + MIN_SECRET_BYTES + " bytes.");
        }
        if (secret.getBytes(StandardCharsets.UTF_8).length < MIN_SECRET_BYTES) {
            throw new IllegalStateException(
                    "coachsync.auth.jwt.secret is too short for HS256 (needs >= " + MIN_SECRET_BYTES
                            + " bytes). Set a longer COACHSYNC_JWT_SECRET.");
        }
    }
}
