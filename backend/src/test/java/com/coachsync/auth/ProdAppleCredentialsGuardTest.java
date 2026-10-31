package com.coachsync.auth;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

import java.security.KeyPairGenerator;
import java.security.spec.ECGenParameterSpec;
import java.util.Base64;

import static org.assertj.core.api.Assertions.assertThat;

class ProdAppleCredentialsGuardTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(ProdAppleCredentialsGuard.class);

    private static AppleRevocationProperties properties(String teamId, String keyId, String key) {
        return new AppleRevocationProperties(teamId, keyId, key, "https://appleid.apple.com");
    }

    private static String realKey() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
        generator.initialize(new ECGenParameterSpec("secp256r1"));
        return "-----BEGIN PRIVATE KEY-----\n"
                + Base64.getMimeEncoder().encodeToString(generator.generateKeyPair().getPrivate().getEncoded())
                + "\n-----END PRIVATE KEY-----";
    }

    @Test
    void prodRefusesToStartWithoutCredentials() {
        runner.withInitializer(ctx -> ctx.getEnvironment().setActiveProfiles("prod"))
                .withBean(AppleRevocationProperties.class, () -> properties("", "", ""))
                .run(ctx -> assertThat(ctx).hasFailed());
    }

    @Test
    void prodRefusesToStartWithAnUnusableKey() {
        runner.withInitializer(ctx -> ctx.getEnvironment().setActiveProfiles("prod"))
                .withBean(AppleRevocationProperties.class, () -> properties("TEAM", "KEY", "not-a-key"))
                .run(ctx -> assertThat(ctx).hasFailed());
    }

    @Test
    void prodStartsWithRealCredentials() throws Exception {
        String key = realKey();
        runner.withInitializer(ctx -> ctx.getEnvironment().setActiveProfiles("prod"))
                .withBean(AppleRevocationProperties.class, () -> properties("TEAM", "KEY", key))
                .run(ctx -> assertThat(ctx).hasNotFailed());
    }

    @Test
    void otherProfilesStartWithoutCredentials() {
        runner.withBean(AppleRevocationProperties.class, () -> properties("", "", ""))
                .run(ctx -> assertThat(ctx).hasNotFailed());
    }
}
