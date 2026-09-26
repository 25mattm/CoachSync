package com.coachsync.web;

import com.coachsync.web.ClubFixtures.ClubFixture;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * {@code Coach} is the one table that cannot carry {@code @TenantId} (it is resolved before any club
 * is known), so its isolation is enforced by hand in {@code CoachService} rather than by Hibernate.
 * This proves a coach in club A cannot see, reach or write club B's coach directory — names and
 * emails are PII too.
 *
 * <p>Not {@code @Transactional} (see {@link CrossClubIsolationTest}); each test uses fresh club ids.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import(ClubFixtures.class)
class CoachIsolationTest {

    @Autowired private MockMvc mvc;
    @Autowired private ClubFixtures fixtures;

    /** A club with one coach already in it, whose token is allowlisted and club-scoped. */
    private ClubFixture club(String coachName) {
        return fixtures.club(coachName);
    }

    private RequestPostProcessor token(ClubFixture f) {
        return fixtures.token(f);
    }

    @Test
    void listReturnsOnlyTheCallersOwnClubCoaches() throws Exception {
        ClubFixture a = club("Alice");
        ClubFixture b = club("Bob");

        // Alice's list contains Alice and never Bob — findAll() is scoped by hand to the club.
        mvc.perform(get("/api/coaches").with(token(a)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content[?(@.name == 'Alice')]").exists())
                .andExpect(jsonPath("$.content[?(@.name == 'Bob')]").doesNotExist());

        // …and symmetrically for Bob.
        mvc.perform(get("/api/coaches").with(token(b)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content[?(@.name == 'Bob')]").exists())
                .andExpect(jsonPath("$.content[?(@.name == 'Alice')]").doesNotExist());
    }

    @Test
    void clubBCannotReadUpdateOrDeleteAClubACoachById() throws Exception {
        ClubFixture a = club("Alice");
        ClubFixture b = club("Bob");

        mvc.perform(get("/api/coaches/{id}", a.coachId()).with(token(b)))
                .andExpect(status().isNotFound());
        mvc.perform(put("/api/coaches/{id}", a.coachId()).with(token(b))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"Hacked\"}"))
                .andExpect(status().isNotFound());
        mvc.perform(delete("/api/coaches/{id}", a.coachId()).with(token(b)))
                .andExpect(status().isNotFound());

        // Alice is untouched.
        mvc.perform(get("/api/coaches/{id}", a.coachId()).with(token(a)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Alice"));
    }

    @Test
    void clubBCannotHijackAClubACoachIdViaCreate() throws Exception {
        ClubFixture a = club("Alice");
        ClubFixture b = club("Bob");

        // Re-POSTing club A's coach id from club B must be a collision (409), never an in-place
        // update of club A's row (Coach lookup is un-tenanted, so this guard is the only thing
        // standing between club B and club A's coach here).
        mvc.perform(post("/api/coaches").with(token(b)).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"id\":\"%s\",\"name\":\"Stolen\"}".formatted(a.coachId())))
                .andExpect(status().isConflict());

        // Club A's coach kept its name.
        mvc.perform(get("/api/coaches/{id}", a.coachId()).with(token(a)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Alice"));
    }
}
