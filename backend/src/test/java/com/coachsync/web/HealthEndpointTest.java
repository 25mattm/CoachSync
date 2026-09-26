package com.coachsync.web;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The health endpoint exists so an uptime check — which cannot present a bearer token — can tell
 * "app up, database down" (503) from "app never started" (no response at all). On 2026-07-09 the
 * managed database was deleted and the app crash-looped for weeks unnoticed, because a free
 * instance that sleeps when idle looks identical to one that cannot start.
 *
 * <p>No {@code @WithMockUser}: the request is deliberately unauthenticated, which is what makes it
 * a regression test for the {@code /actuator/health} permit in {@link com.coachsync.auth.SecurityConfig}.
 */
@SpringBootTest
@AutoConfigureMockMvc
class HealthEndpointTest {

    @Autowired private MockMvc mvc;

    @Test
    void healthIsServedWithoutAuth() throws Exception {
        mvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }

    /**
     * The endpoint is anonymous, so it must not narrate the infrastructure behind it: no component
     * breakdown, and in particular no {@code db} entry naming the driver or database.
     */
    @Test
    void healthLeaksNoInfrastructureDetailToAnonymousCallers() throws Exception {
        mvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.components").doesNotExist())
                .andExpect(jsonPath("$.details").doesNotExist())
                .andExpect(jsonPath("$.db").doesNotExist());
    }

    /**
     * Only {@code health} is exposed. If someone widens
     * {@code management.endpoints.web.exposure.include}, {@code /actuator/env} would hand an
     * anonymous caller the datasource URL — this fails first.
     */
    @Test
    void otherActuatorEndpointsAreNotExposed() throws Exception {
        mvc.perform(get("/actuator/env"))
                .andExpect(status().is4xxClientError());
    }
}
