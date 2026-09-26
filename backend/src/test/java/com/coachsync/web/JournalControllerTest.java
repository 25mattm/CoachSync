package com.coachsync.web;

import com.coachsync.web.ClubFixtures.ClubFixture;
import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * A journal entry (and the athlete it's attached to) must both be created under the SAME real
 * club-scoped fixture coach — an athlete created via a direct repository save under the class's
 * ambient {@code @WithMockUser} (which resolves {@code NO_TENANT}) would be invisible to a request
 * authenticated with a real club claim.
 */
@SpringBootTest
@AutoConfigureMockMvc
@WithMockUser
@Transactional
@Import(ClubFixtures.class)
class JournalControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private ClubFixtures fixtures;

    private UUID newAthlete(RequestPostProcessor as) throws Exception {
        String body = mvc.perform(post("/api/athletes").with(as)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"firstName\":\"Ada\",\"lastName\":\"Paddle\",\"dateOfBirth\":\"2012-01-01\"}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return UUID.fromString(JsonPath.read(body, "$.id"));
    }

    private String createJournal(RequestPostProcessor as, UUID athleteId, String json) throws Exception {
        String body = mvc.perform(post("/api/athletes/{id}/journal", athleteId)
                        .with(as)
                        .contentType(MediaType.APPLICATION_JSON).content(json))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", containsString("/api/journal/")))
                .andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.id");
    }

    @Test
    void createsJournalWithTagsAndCoach() throws Exception {
        ClubFixture f = fixtures.club();
        RequestPostProcessor as = fixtures.token(f);
        UUID athleteId = newAthlete(as);
        // The "logged by" coach is the authenticated principal, not a body field.
        String id = createJournal(as, athleteId,
                "{\"date\":\"2026-06-16\",\"text\":\"Strong week\",\"tags\":[\"Technique\",\"Mindset\"]}");

        mvc.perform(get("/api/journal/{id}", id).with(as))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.text", is("Strong week")))
                .andExpect(jsonPath("$.tags", hasSize(2)))
                .andExpect(jsonPath("$.tags[0]", is("Technique")))
                .andExpect(jsonPath("$.coachId", is(f.coachId().toString())));
    }

    @Test
    void blankTextReturns400() throws Exception {
        // @Valid rejects blank text before the controller body runs, so the athlete id never needs to
        // resolve to a real row — a bare random UUID proves the same thing without the DB/HTTP round
        // trip a real fixture would cost. Also deliberately not club-scoped, to prove validation fires
        // regardless.
        mvc.perform(post("/api/athletes/{id}/journal", UUID.randomUUID()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"date\":\"2026-06-16\",\"text\":\"\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void unknownPrincipalCoachReturns401() throws Exception {
        RequestPostProcessor as = fixtures.token(fixtures.club());
        UUID athleteId = newAthlete(as);
        // A token whose subject isn't a real coach is rejected up front by ActiveCoachFilter.
        mvc.perform(post("/api/athletes/{id}/journal", athleteId)
                        .with(jwt().jwt(j -> j.subject(UUID.randomUUID().toString())))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"date\":\"2026-06-16\",\"text\":\"Note\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void updateReplacesTextAndTags() throws Exception {
        RequestPostProcessor as = fixtures.token(fixtures.club());
        UUID athleteId = newAthlete(as);
        String id = createJournal(as, athleteId, "{\"date\":\"2026-06-16\",\"text\":\"Old\",\"tags\":[\"A\",\"B\"]}");
        mvc.perform(put("/api/journal/{id}", id).with(as).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"date\":\"2026-06-16\",\"text\":\"New\",\"tags\":[\"C\"]}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.text", is("New")))
                .andExpect(jsonPath("$.tags", hasSize(1)))
                .andExpect(jsonPath("$.tags[0]", is("C")));
    }

    @Test
    void deletesJournalEntry() throws Exception {
        RequestPostProcessor as = fixtures.token(fixtures.club());
        UUID athleteId = newAthlete(as);
        String id = createJournal(as, athleteId, "{\"date\":\"2026-06-16\",\"text\":\"Note\"}");
        mvc.perform(delete("/api/journal/{id}", id).with(as)).andExpect(status().isNoContent());
        mvc.perform(get("/api/journal/{id}", id).with(as)).andExpect(status().isNotFound());
    }

    @Test
    void athleteWithJournalCannotBeDeleted() throws Exception {
        RequestPostProcessor as = fixtures.token(fixtures.club());
        UUID athleteId = newAthlete(as);
        createJournal(as, athleteId, "{\"date\":\"2026-06-16\",\"text\":\"Note\"}");
        mvc.perform(delete("/api/athletes/{id}", athleteId).with(as)).andExpect(status().isConflict());
    }

    @Test
    void coachReferencedByJournalCannotBeDeleted() throws Exception {
        // The coach must be in the caller's club for delete to reach the reference guard rather than
        // 404 on the club check (CoachService now scopes coach lookups — see CoachIsolationTest).
        ClubFixture f = fixtures.club();
        RequestPostProcessor as = fixtures.token(f);
        UUID athleteId = newAthlete(as);
        // Attribution comes from the authenticated principal; the entry then references the coach.
        createJournal(as, athleteId, "{\"date\":\"2026-06-16\",\"text\":\"Note\"}");
        mvc.perform(delete("/api/coaches/{id}", f.coachId()).with(as))
                .andExpect(status().isConflict());
    }

    @Test
    void createForUnknownAthleteReturns404() throws Exception {
        // A real coach principal (so ActiveCoachFilter passes) but a non-existent athlete.
        mvc.perform(post("/api/athletes/{id}/journal", UUID.randomUUID())
                        .with(fixtures.token(fixtures.club()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"date\":\"2026-06-16\",\"text\":\"Note\"}"))
                .andExpect(status().isNotFound());
    }
}
