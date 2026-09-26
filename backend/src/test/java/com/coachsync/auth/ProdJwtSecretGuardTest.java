package com.coachsync.auth;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

import java.time.Duration;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Verifies the prod fail-fast guard for the JWT signing secret. The assertion is on whether the
 * application context startup itself fails, so this uses {@link ApplicationContextRunner} rather
 * than {@code @SpringBootTest} (which can't cleanly assert a deliberate startup failure).
 */
class ProdJwtSecretGuardTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(ProdJwtSecretGuard.class);

    private static AuthProperties propsWithSecret(String secret) {
        return new AuthProperties(
                new AuthProperties.Apple("https://appleid.apple.com",
                        "https://appleid.apple.com/auth/keys", List.of("com.example.app")),
                new AuthProperties.Jwt(secret, "coachsync-backend", Duration.ofDays(30)),
                List.of());
    }

    @Test
    void prodRefusesToStartWithTheCommittedDevDefault() {
        runner.withInitializer(ctx -> ctx.getEnvironment().setActiveProfiles("prod"))
                .withBean(AuthProperties.class, () -> propsWithSecret(AuthProperties.DEV_DEFAULT_JWT_SECRET))
                .run(ctx -> assertThat(ctx).hasFailed());
    }

    @Test
    void prodRefusesToStartWithATooShortSecret() {
        runner.withInitializer(ctx -> ctx.getEnvironment().setActiveProfiles("prod"))
                .withBean(AuthProperties.class, () -> propsWithSecret("too-short"))
                .run(ctx -> assertThat(ctx).hasFailed());
    }

    @Test
    void prodStartsWithAStrongOverriddenSecret() {
        runner.withInitializer(ctx -> ctx.getEnvironment().setActiveProfiles("prod"))
                .withBean(AuthProperties.class,
                        () -> propsWithSecret("a-private-production-jwt-secret-that-is-clearly-long-enough"))
                .run(ctx -> assertThat(ctx).hasNotFailed());
    }

    @Test
    void devProfileToleratesTheDefaultSecret() {
        // No prod profile → the guard never registers → the convenient default is fine for local dev.
        runner.withBean(AuthProperties.class, () -> propsWithSecret(AuthProperties.DEV_DEFAULT_JWT_SECRET))
                .run(ctx -> assertThat(ctx).hasNotFailed());
    }
}
