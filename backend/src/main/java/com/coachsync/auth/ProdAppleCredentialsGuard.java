package com.coachsync.auth;

import jakarta.annotation.PostConstruct;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import java.security.GeneralSecurityException;

/**
 * Fail-fast: refuses to start the {@code prod} profile without working Apple credentials. Without
 * them, account deletion can't confirm the Apple authorization or revoke the Sign in with Apple
 * grant, and nothing would show that except a log line per deletion.
 */
@Component
@Profile("prod")
public class ProdAppleCredentialsGuard {

    private final AppleRevocationProperties properties;

    public ProdAppleCredentialsGuard(AppleRevocationProperties properties) {
        this.properties = properties;
    }

    @PostConstruct
    void verifyCredentials() {
        if (!properties.isConfigured()) {
            throw new IllegalStateException("Apple credentials are not set. Set COACHSYNC_APPLE_TEAM_ID, "
                    + "COACHSYNC_APPLE_KEY_ID and COACHSYNC_APPLE_PRIVATE_KEY before starting the prod profile.");
        }
        try {
            HttpAppleGrantClient.parsePrivateKey(properties.privateKey());
        } catch (GeneralSecurityException | IllegalArgumentException | ClassCastException ex) {
            throw new IllegalStateException("COACHSYNC_APPLE_PRIVATE_KEY isn't a PKCS#8 EC private key.");
        }
    }
}
