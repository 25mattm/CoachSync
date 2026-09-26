package com.coachsync.web;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;

import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Smoke test for the springdoc OpenAPI surface: the generated spec is served,
 * reachable without authentication (SecurityConfig permits the docs paths), and
 * actually enumerates the REST API. Guards against a springdoc/Spring upgrade
 * silently breaking spec generation. No {@code @WithMockUser} — the request is
 * deliberately unauthenticated to prove the permit.
 */
@SpringBootTest
@AutoConfigureMockMvc
class OpenApiDocsTest {

    @Autowired private MockMvc mvc;

    @Test
    void apiDocsAreServedWithoutAuthAndDescribeTheApi() throws Exception {
        mvc.perform(get("/v3/api-docs"))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString("\"openapi\"")))
                .andExpect(jsonPath("$.info.title").value("CoachSync API"))
                .andExpect(jsonPath("$.paths['/api/athletes']").exists())
                .andExpect(jsonPath("$.components.securitySchemes.bearerAuth.scheme").value("bearer"));
    }
}
