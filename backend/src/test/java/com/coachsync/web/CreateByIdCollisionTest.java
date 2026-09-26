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

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The sync engine lets a client choose an entity's UUID (POST-with-id, last-write-wins), so an
 * attacker in club B could POST an athlete carrying a club-A athlete's id. Under the tenant filter
 * club B's {@code findById} misses club A's row, so the create falls through to an insert that hits
 * the global primary key. This pins the outcome: a clean <b>409</b> — never a 500 (which would be an
 * existence oracle for another club's ids), never a silent insert, and never an overwrite of club
 * A's row.
 *
 * <p>Not {@code @Transactional} (see {@link CrossClubIsolationTest}); fresh club ids per test.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import(ClubFixtures.class)
class CreateByIdCollisionTest {

    @Autowired private MockMvc mvc;
    @Autowired private ClubFixtures fixtures;

    private ClubFixture club() {
        return fixtures.club("Coach");
    }

    private RequestPostProcessor token(ClubFixture f) {
        return fixtures.token(f);
    }

    private static final String ADA = """
            {"firstName":"Ada","lastName":"Lovelace","dateOfBirth":"2014-05-01","gender":"FEMALE"}
            """;

    @Test
    void clubBCannotHijackAClubAAthleteIdViaCreate() throws Exception {
        ClubFixture a = club();
        ClubFixture b = club();

        String athleteId = mvc.perform(post("/api/athletes").with(token(a))
                        .contentType(MediaType.APPLICATION_JSON).content(ADA))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString()
                .replaceAll("(?s).*\"id\"\\s*:\\s*\"([^\"]+)\".*", "$1");

        // Club B re-uses club A's athlete id.
        mvc.perform(post("/api/athletes").with(token(b)).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"id\":\"%s\",\"firstName\":\"Stolen\",\"lastName\":\"X\",\"dateOfBirth\":\"2014-05-01\",\"gender\":\"FEMALE\"}"
                                .formatted(athleteId)))
                .andExpect(status().isConflict());

        // Club A's athlete is untouched — same name, still present.
        mvc.perform(get("/api/athletes/{id}", athleteId).with(token(a)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.firstName").value("Ada"));

        // …and club B still cannot see it.
        mvc.perform(get("/api/athletes/{id}", athleteId).with(token(b)))
                .andExpect(status().isNotFound());
    }
}
