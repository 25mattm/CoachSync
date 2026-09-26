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

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * A tenant-scoped {@code /{id}} route being 404 across clubs is not enough on its own: an endpoint
 * that stitches a body-supplied id onto one of the caller's own rows could smuggle another club's
 * data in sideways. This proves the two such paths refuse a cross-club id — attaching a club-A
 * athlete to a club-B session's attendance, and assigning a club-A team to a new club-B session.
 * Both are safe because the resolving lookups ({@code findAllById}, {@code teams.findById}) run
 * through the tenant filter, so a foreign id simply is not found.
 *
 * <p>Not {@code @Transactional} (see {@link CrossClubIsolationTest}); fresh club ids per test.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import(ClubFixtures.class)
class RelationshipIsolationTest {

    @Autowired private MockMvc mvc;
    @Autowired private ClubFixtures fixtures;

    private ClubFixture club() {
        return fixtures.club("Coach");
    }

    private RequestPostProcessor token(ClubFixture f) {
        return fixtures.token(f);
    }

    private String create(RequestPostProcessor tok, String path, String body) throws Exception {
        return mvc.perform(post(path).with(tok).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString()
                .replaceAll("(?s).*\"id\"\\s*:\\s*\"([^\"]+)\".*", "$1");
    }

    @Test
    void clubBCannotAttachAClubAAthleteToItsOwnSessionAttendance() throws Exception {
        ClubFixture a = club();
        ClubFixture b = club();

        String clubAAthlete = create(token(a), "/api/athletes",
                "{\"firstName\":\"Ada\",\"lastName\":\"Lovelace\",\"dateOfBirth\":\"2014-05-01\",\"gender\":\"FEMALE\"}");
        String clubBSession = create(token(b), "/api/sessions",
                "{\"sessionName\":\"B Practice\",\"scheduledDate\":\"2026-06-16\"}");

        // Club B owns the session but the athlete belongs to club A — findAllById is tenant-filtered,
        // so the athlete is "not found" and the whole upsert 404s rather than stitching across clubs.
        mvc.perform(put("/api/sessions/{sid}/attendance", clubBSession).with(token(b))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"entries\":[{\"athleteId\":\"%s\",\"status\":\"PRESENT\"}]}".formatted(clubAAthlete)))
                .andExpect(status().isNotFound());
    }

    @Test
    void clubBCannotAssignAClubATeamToItsOwnSession() throws Exception {
        ClubFixture a = club();
        ClubFixture b = club();

        String clubATeam = create(token(a), "/api/teams", "{\"teamName\":\"A Squad\"}");

        mvc.perform(post("/api/sessions").with(token(b)).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"sessionName\":\"B Practice\",\"scheduledDate\":\"2026-06-16\",\"teamId\":\"%s\"}"
                                .formatted(clubATeam)))
                .andExpect(status().isNotFound());
    }
}
