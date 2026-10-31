package com.coachsync.auth;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * Credentials for calling Apple's token endpoints, bound from
 * {@code coachsync.auth.apple.revocation.*}. Every value but {@code baseUrl} comes from the
 * environment and stays out of the repo; revocation is skipped, with a warning, until all are set.
 *
 * @param teamId     Apple Developer team ID.
 * @param keyId      ID of the Sign in with Apple key.
 * @param privateKey the key's PKCS#8 PEM contents.
 * @param baseUrl    Apple's endpoint root; overridden only by tests.
 */
@ConfigurationProperties("coachsync.auth.apple.revocation")
public record AppleRevocationProperties(
        String teamId,
        String keyId,
        String privateKey,
        @DefaultValue("https://appleid.apple.com") String baseUrl) {

    boolean isConfigured() {
        return present(teamId) && present(keyId) && present(privateKey);
    }

    private static boolean present(String value) {
        return value != null && !value.isBlank();
    }
}
