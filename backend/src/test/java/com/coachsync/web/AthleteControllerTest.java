package com.coachsync.web;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.AthleteNote;
import com.coachsync.domain.CoachSession;
import com.coachsync.repository.AthleteNoteRepository;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.CoachSessionRepository;
import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.UUID;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.is;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * End-to-end MockMvc tests for the Athlete API — exercises the controller, the
 * DTO mapping, validation, the ProblemDetail error model, and the
 * recorded-history deletion guard against in-memory H2. Each test runs in a
 * rolled-back transaction.
 */
@SpringBootTest
@AutoConfigureMockMvc
@WithMockUser
@Transactional
class AthleteControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private AthleteRepository athletes;
    @Autowired private CoachSessionRepository sessions;
    @Autowired private AthleteNoteRepository notes;

    private String payload(String firstName, String lastName) {
        return """
                {"firstName":"%s","lastName":"%s","dateOfBirth":"2014-05-01","gender":"FEMALE"}
                """.formatted(firstName, lastName);
    }

    private String createAthlete(String first, String last) throws Exception {
        String body = mvc.perform(post("/api/athletes")
                        .contentType(MediaType.APPLICATION_JSON).content(payload(first, last)))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", containsString("/api/athletes/")))
                .andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.id");
    }

    @Test
    void createsThenReadsAthlete() throws Exception {
        String id = createAthlete("Ada", "Paddle");
        mvc.perform(get("/api/athletes/{id}", id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.firstName", is("Ada")))
                .andExpect(jsonPath("$.lastName", is("Paddle")))
                .andExpect(jsonPath("$.active", is(true)))
                .andExpect(jsonPath("$.developmentStage", is("INITIATION")));
    }

    @Test
    void updatesAthlete() throws Exception {
        String id = createAthlete("Before", "Name");
        String updated = """
                {"firstName":"After","lastName":"Renamed","dateOfBirth":"2012-02-02","gender":"MALE","developmentStage":"ACQUISITION"}
                """;
        mvc.perform(put("/api/athletes/{id}", id)
                        .contentType(MediaType.APPLICATION_JSON).content(updated))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.firstName", is("After")))
                .andExpect(jsonPath("$.developmentStage", is("ACQUISITION")));
        mvc.perform(get("/api/athletes/{id}", id))
                .andExpect(jsonPath("$.lastName", is("Renamed")))
                .andExpect(jsonPath("$.gender", is("MALE")));
    }

    @Test
    void putWithoutDevelopmentStageResetsToDefault() throws Exception {
        String id = createAthlete("Stage", "Reset");
        mvc.perform(put("/api/athletes/{id}", id).contentType(MediaType.APPLICATION_JSON).content("""
                {"firstName":"Stage","lastName":"Reset","dateOfBirth":"2012-02-02","developmentStage":"ACQUISITION"}
                """)).andExpect(jsonPath("$.developmentStage", is("ACQUISITION")));
        mvc.perform(put("/api/athletes/{id}", id).contentType(MediaType.APPLICATION_JSON).content("""
                {"firstName":"Stage","lastName":"Reset","dateOfBirth":"2012-02-02"}
                """)).andExpect(jsonPath("$.developmentStage", is("INITIATION")));
    }

    @Test
    void unknownAthleteReturns404() throws Exception {
        mvc.perform(get("/api/athletes/{id}", UUID.randomUUID()))
                .andExpect(status().isNotFound());
    }

    @Test
    void blankFirstNameReturns400WithFieldError() throws Exception {
        mvc.perform(post("/api/athletes")
                        .contentType(MediaType.APPLICATION_JSON).content(payload("", "Paddle")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors.firstName").exists());
    }

    @Test
    void overLongOrInvalidFieldsReturn400() throws Exception {
        String longName = "x".repeat(300);
        mvc.perform(post("/api/athletes").contentType(MediaType.APPLICATION_JSON).content("""
                {"firstName":"%s","lastName":"Ok","dateOfBirth":"2014-05-01"}
                """.formatted(longName)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors.firstName").exists());
        mvc.perform(post("/api/athletes").contentType(MediaType.APPLICATION_JSON).content("""
                {"firstName":"Ok","lastName":"Ok","dateOfBirth":"2014-05-01","guardianEmail":"not-an-email"}
                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors.guardianEmail").exists());
    }

    @Test
    void malformedBodyYieldsProblemDetail() throws Exception {
        mvc.perform(post("/api/athletes").contentType(MediaType.APPLICATION_JSON).content("{ not json }"))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"));
    }

    @Test
    void listsActiveAthletes() throws Exception {
        createAthlete("List", "Me");
        mvc.perform(get("/api/athletes").param("active", "true"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content[*].firstName", hasItem("List")));
    }

    @Test
    void patchTogglesActive() throws Exception {
        String id = createAthlete("Toggle", "Active");
        mvc.perform(patch("/api/athletes/{id}/active", id).param("value", "false"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.active", is(false)));
    }

    @Test
    void deletesAthleteWithoutHistory() throws Exception {
        String id = createAthlete("Gone", "Soon");
        mvc.perform(delete("/api/athletes/{id}", id)).andExpect(status().isNoContent());
        mvc.perform(get("/api/athletes/{id}", id)).andExpect(status().isNotFound());
    }

    @Test
    void deleteAthleteWithHistoryReturns409() throws Exception {
        Athlete athlete = new Athlete();
        athlete.setFirstName("Has");
        athlete.setLastName("History");
        athlete.setDateOfBirth(LocalDate.of(2013, 3, 3));
        athlete = athletes.save(athlete);

        CoachSession session = new CoachSession();
        session.setSessionName("Practice");
        session.setScheduledDate(LocalDate.of(2026, 6, 16));
        session = sessions.save(session);

        AthleteNote note = new AthleteNote();
        note.setNoteText("Strong catch today");
        note.setAthlete(athlete);
        note.setSession(session);
        notes.save(note);

        mvc.perform(delete("/api/athletes/{id}", athlete.getId()))
                .andExpect(status().isConflict());
    }

    // --- Last-write-wins skip-stale (Phase 2 Stage 3a) -----------------------

    @Test
    void staleUpdateIsIgnoredAndNewerWins() throws Exception {
        // Create with a known client edit time; the server stores it verbatim.
        String created = mvc.perform(post("/api/athletes").contentType(MediaType.APPLICATION_JSON).content("""
                {"firstName":"Orig","lastName":"Name","dateOfBirth":"2014-05-01","updatedAt":"2025-06-01T00:00:00Z"}
                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.updatedAt", containsString("2025-06-01")))
                .andReturn().getResponse().getContentAsString();
        String id = JsonPath.read(created, "$.id");

        // A write not newer than the stored copy is ignored (data + timestamp unchanged).
        mvc.perform(put("/api/athletes/{id}", id).contentType(MediaType.APPLICATION_JSON).content("""
                {"firstName":"Stale","lastName":"Loser","dateOfBirth":"2014-05-01","updatedAt":"2025-01-01T00:00:00Z"}
                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.firstName", is("Orig")))
                .andExpect(jsonPath("$.updatedAt", containsString("2025-06-01")));
        mvc.perform(get("/api/athletes/{id}", id))
                .andExpect(jsonPath("$.firstName", is("Orig")));

        // A newer write is applied and its timestamp stored verbatim.
        mvc.perform(put("/api/athletes/{id}", id).contentType(MediaType.APPLICATION_JSON).content("""
                {"firstName":"Fresh","lastName":"Winner","dateOfBirth":"2014-05-01","updatedAt":"2025-12-01T00:00:00Z"}
                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.firstName", is("Fresh")))
                .andExpect(jsonPath("$.updatedAt", containsString("2025-12-01")));
    }

    @Test
    void updateWithoutTimestampStillApplies() throws Exception {
        // A legacy / non-sync client that omits updatedAt is never treated as stale.
        String id = createAthlete("Legacy", "Client");
        mvc.perform(put("/api/athletes/{id}", id).contentType(MediaType.APPLICATION_JSON).content("""
                {"firstName":"Changed","lastName":"Client","dateOfBirth":"2014-05-01"}
                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.firstName", is("Changed")));
    }

    @Test
    void postHonorsClientIdAndActiveFlag() throws Exception {
        String id = UUID.randomUUID().toString();
        // Id-matched sync: the backend persists the app's own id, and the full-state body
        // carries isActive (created inactive here).
        mvc.perform(post("/api/athletes").contentType(MediaType.APPLICATION_JSON).content("""
                {"id":"%s","firstName":"Synced","lastName":"Athlete","dateOfBirth":"2014-05-01","active":false}
                """.formatted(id)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id", is(id)))
                .andExpect(jsonPath("$.active", is(false)));
        // A full-state PUT reactivates.
        mvc.perform(put("/api/athletes/{id}", id).contentType(MediaType.APPLICATION_JSON).content("""
                {"firstName":"Synced","lastName":"Athlete","dateOfBirth":"2014-05-01","active":true}
                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.active", is(true)));
    }

    @Test
    void rePostWithStaleIdDoesNotClobberNewerRow() throws Exception {
        String id = UUID.randomUUID().toString();
        mvc.perform(post("/api/athletes").contentType(MediaType.APPLICATION_JSON).content("""
                {"id":"%s","firstName":"Fresh","lastName":"Row","dateOfBirth":"2014-05-01","updatedAt":"2030-01-01T00:00:00Z"}
                """.formatted(id)))
                .andExpect(status().isCreated());
        // A re-sent older insert for the same id (e.g. retry after a lost response, while another
        // device already edited it) must NOT overwrite the newer row — last-write-wins on create.
        mvc.perform(post("/api/athletes").contentType(MediaType.APPLICATION_JSON).content("""
                {"id":"%s","firstName":"Stale","lastName":"Row","dateOfBirth":"2014-05-01","updatedAt":"2020-01-01T00:00:00Z"}
                """.formatted(id)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.firstName", is("Fresh")));
    }
}
