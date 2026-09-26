package com.coachsync.web;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Describes the generated OpenAPI document (title/version) and declares the
 * HTTP bearer (JWT) security scheme, so the Swagger UI "Authorize" button accepts
 * a backend session token from {@code POST /api/auth/apple}. The requirement is
 * applied globally because nearly every {@code /api/**} endpoint is JWT-locked;
 * the public sign-in and docs paths remain callable without one.
 */
@Configuration
public class OpenApiConfig {

    private static final String BEARER_SCHEME = "bearerAuth";

    @Bean
    OpenAPI coachSyncOpenAPI() {
        return new OpenAPI()
                .info(new Info()
                        .title("CoachSync API")
                        .description("REST API for the CoachSync backend — athletes, teams, "
                                + "sessions, attendance, performance, assessments, and analytics. "
                                + "Authenticate via Sign in with Apple at POST /api/auth/apple, then "
                                + "send the returned token as a Bearer header on /api/** calls.")
                        .version("v1"))
                .components(new Components().addSecuritySchemes(BEARER_SCHEME,
                        new SecurityScheme()
                                .type(SecurityScheme.Type.HTTP)
                                .scheme("bearer")
                                .bearerFormat("JWT")
                                .description("Backend session JWT issued by POST /api/auth/apple")))
                .addSecurityItem(new SecurityRequirement().addList(BEARER_SCHEME));
    }
}
