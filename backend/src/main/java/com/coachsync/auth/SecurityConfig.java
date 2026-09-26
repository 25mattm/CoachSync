package com.coachsync.auth;

import com.coachsync.repository.CoachRepository;
import com.nimbusds.jose.jwk.source.ImmutableSecret;
import com.nimbusds.jose.proc.SecurityContext;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtIssuerValidator;
import org.springframework.security.oauth2.jwt.JwtTimestampValidator;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.jwt.NimbusJwtEncoder;
import org.springframework.security.oauth2.server.resource.web.authentication.BearerTokenAuthenticationFilter;
import org.springframework.security.web.SecurityFilterChain;

import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * Locks the API: every {@code /api/**} call requires a valid backend JWT (Bearer), except
 * the public {@code /api/auth/**} sign-in endpoints and the OpenAPI/Swagger docs
 * ({@code /v3/api-docs/**}, {@code /swagger-ui/**}). Stateless; CSRF disabled (token-based).
 *
 * <p>Our own tokens are HS256 — one secret both signs (the {@link JwtEncoder}) and verifies
 * (the resource-server {@link JwtDecoder}). The single {@code JwtDecoder} bean is for our
 * tokens; Apple's decoder lives inside {@link NimbusAppleTokenVerifier}, so there is no
 * decoder-bean ambiguity. Defining our own {@code JwtDecoder} also makes Spring Boot's
 * resource-server auto-config back off (no {@code issuer-uri}/{@code jwk-set-uri} required).
 */
@Configuration
@EnableConfigurationProperties(AuthProperties.class)
public class SecurityConfig {

    /**
     * Routes that need no authentication at all. {@link ClubMembershipWriteGuard} also skips any
     * request matching one of these before doing its own club-membership check — one list, not two
     * independently-maintained ones. Without this, a bearer token attached to a public route (Spring
     * Security authenticates any request carrying one, whether or not the target route needs it)
     * would reach the guard as an ordinary authenticated request; a future mutating public route not
     * also added to {@code ClubMembershipWriteGuard}'s own bootstrap allowlist would then be wrongly
     * 403'd for a club-less caller instead of honoring {@code permitAll()}.
     */
    static final List<String> PUBLIC_PATHS = List.of(
            "/api/auth/**", "/actuator/health", "/v3/api-docs/**", "/swagger-ui/**", "/swagger-ui.html");

    // Only a servlet web context has HttpSecurity; non-web @SpringBootTest(webEnvironment = NONE)
    // contexts (persistence/slot-gen tests) load the rest of the beans but skip the filter chain.
    @Bean
    @ConditionalOnWebApplication(type = ConditionalOnWebApplication.Type.SERVLET)
    SecurityFilterChain filterChain(HttpSecurity http, JwtDecoder jwtDecoder, CoachRepository coaches,
            ClubTenantResolver tenant)
            throws Exception {
        http
                .authorizeHttpRequests(auth -> auth
                        // Liveness for uptime checks, which cannot present a bearer token. Safe to
                        // expose: management.endpoint.health.show-details=never means the body is a
                        // bare {"status":"UP"} — no datasource URL, driver, or schema. Only /health
                        // is exposed (management.endpoints.web.exposure.include), so this matcher
                        // cannot reach /actuator/env or the other endpoints.
                        // Docs are permitted for dev/test only; the prod profile disables springdoc
                        // entirely (springdoc.*.enabled=false) so these match nothing in production.
                        .requestMatchers(PUBLIC_PATHS.toArray(String[]::new)).permitAll()
                        .anyRequest().authenticated())
                .csrf(csrf -> csrf.disable())
                .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .oauth2ResourceServer(oauth2 -> oauth2.jwt(jwt -> jwt.decoder(jwtDecoder)))
                // Per-request revocation: a valid token whose coach was deleted OR moved out of the
                // club its token claims is rejected (401) right after bearer authentication, not
                // honored for the rest of its 30-day life.
                .addFilterAfter(new ActiveCoachFilter(coaches), BearerTokenAuthenticationFilter.class)
                // Closes the pending-coach write hole: a club-less caller's mutating request is
                // rejected (403) unless it targets a public route (PUBLIC_PATHS) or one of the three
                // bootstrap routes for getting into a club. See ClubMembershipWriteGuard's javadoc.
                .addFilterAfter(new ClubMembershipWriteGuard(tenant, PUBLIC_PATHS), ActiveCoachFilter.class);
        return http.build();
    }

    /** Verifies our own HS256 tokens (signature + timestamp + issuer). */
    @Bean
    JwtDecoder jwtDecoder(AuthProperties props) {
        NimbusJwtDecoder decoder = NimbusJwtDecoder.withSecretKey(hmacKey(props.jwt().secret()))
                .macAlgorithm(MacAlgorithm.HS256)
                .build();
        decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(
                new JwtTimestampValidator(),
                new JwtIssuerValidator(props.jwt().issuer())));
        return decoder;
    }

    /** Signs our own HS256 tokens with the shared secret. */
    @Bean
    JwtEncoder jwtEncoder(AuthProperties props) {
        return new NimbusJwtEncoder(new ImmutableSecret<SecurityContext>(hmacKey(props.jwt().secret())));
    }

    private static SecretKey hmacKey(String secret) {
        return new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256");
    }
}
