package com.coachsync.web;

import com.coachsync.web.ClubFixtures.ClubFixture;
import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Sync-write rules that keep one client's bad input from corrupting shared club data: a clock
 * running ahead can't freeze a row, a rep result must fit its block, a re-sent id can't silently
 * re-parent (or pretend to re-parent) a child row, and a completed session stays completed.
 *
 * <p>Not {@code @Transactional} (see {@link CrossClubIsolationTest}); a fresh club per test.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import(ClubFixtures.class)
class SyncWriteIntegrityTest {

    @Autowired private MockMvc mvc;
    @Autowired private ClubFixtures fixtures;

    private RequestPostProcessor token;

    @BeforeEach
    void freshClub() {
        ClubFixture club = fixtures.club();
        token = fixtures.token(club);
    }

    private String postJson(String path, String body, Object... uriVars) throws Exception {
        String response = mvc.perform(post(path, uriVars).with(token)
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return JsonPath.read(response, "$.id");
    }

    private String athlete(String firstName) throws Exception {
        return postJson("/api/athletes", """
                {"firstName":"%s","lastName":"Test","dateOfBirth":"2014-05-01"}
                """.formatted(firstName));
    }

    private String session(String name) throws Exception {
        return postJson("/api/sessions", """
                {"sessionName":"%s","scheduledDate":"2026-06-01"}
                """.formatted(name));
    }

    // --- Clock skew -----------------------------------------------------------------------------

    @Test
    void aClockRunningAheadCannotFreezeARowForCorrectlyClockedCoaches() throws Exception {
        Instant tomorrow = Instant.now().plus(Duration.ofDays(1));
        String id = postJson("/api/athletes", """
                {"firstName":"Ahead","lastName":"Clock","dateOfBirth":"2014-05-01","updatedAt":"%s"}
                """.formatted(tomorrow));

        // A later edit from a device with a correct clock must still win.
        mvc.perform(put("/api/athletes/{id}", id).with(token).contentType(MediaType.APPLICATION_JSON).content("""
                        {"firstName":"Correct","lastName":"Clock","dateOfBirth":"2014-05-01","updatedAt":"%s"}
                        """.formatted(Instant.now())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.firstName", is("Correct")));
    }

    // --- Rep numbers must fit the block ---------------------------------------------------------

    @Test
    void repResultsOutsideTheBlocksRepsAreRejected() throws Exception {
        String athleteId = athlete("Rower");
        String sessionId = session("Reps");
        String blockId = postJson("/api/sessions/{sessionId}/blocks", """
                {"blockName":"4 x 500","blockType":"PADDLE_DISTANCE","repetitionCount":4}
                """, sessionId);
        String entry = "{\"entries\":[{\"athleteId\":\"" + athleteId + "\",\"repNumber\":%d,"
                + "\"status\":\"COMPLETE\",\"recordedTimeMs\":120000}]}";

        for (int outside : new int[] {0, -1, 5}) {
            mvc.perform(put("/api/blocks/{blockId}/performance", blockId).with(token)
                            .contentType(MediaType.APPLICATION_JSON).content(entry.formatted(outside)))
                    .andExpect(status().isBadRequest());
        }
        mvc.perform(put("/api/blocks/{blockId}/performance", blockId).with(token)
                        .contentType(MediaType.APPLICATION_JSON).content(entry.formatted(4)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].repNumber", is(4)));
    }

    @Test
    void aNoteOnlyBlockAcceptsNoRepResults() throws Exception {
        String athleteId = athlete("Lifter");
        String sessionId = session("Gym");
        String blockId = postJson("/api/sessions/{sessionId}/blocks", """
                {"blockName":"Weights","blockType":"WEIGHTS"}
                """, sessionId);

        mvc.perform(put("/api/blocks/{blockId}/performance", blockId).with(token)
                        .contentType(MediaType.APPLICATION_JSON).content(
                        "{\"entries\":[{\"athleteId\":\"" + athleteId + "\",\"repNumber\":1,\"status\":\"DNS\"}]}"))
                .andExpect(status().isBadRequest());
    }

    // --- A re-sent id cannot move a child row to another parent ---------------------------------

    @Test
    void reSendingAHeightUnderAnotherAthleteIsAConflict() throws Exception {
        String first = athlete("First");
        String second = athlete("Second");
        String heightId = UUID.randomUUID().toString();
        postJson("/api/athletes/{athleteId}/heights", """
                {"id":"%s","heightCm":150.0,"date":"2026-05-01"}
                """.formatted(heightId), first);

        mvc.perform(post("/api/athletes/{athleteId}/heights", second).with(token)
                        .contentType(MediaType.APPLICATION_JSON).content("""
                        {"id":"%s","heightCm":190.0,"date":"2026-05-02"}
                        """.formatted(heightId)))
                .andExpect(status().isConflict());

        mvc.perform(get("/api/heights/{id}", heightId).with(token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.athleteId", is(first)))
                .andExpect(jsonPath("$.heightCm", is(150.0)));
    }

    @Test
    void reSendingABlockUnderAnotherSessionIsAConflict() throws Exception {
        String sessionX = session("X");
        String sessionY = session("Y");
        String blockId = UUID.randomUUID().toString();
        postJson("/api/sessions/{sessionId}/blocks", """
                {"id":"%s","blockName":"Original","blockType":"TECHNIQUE"}
                """.formatted(blockId), sessionX);

        mvc.perform(post("/api/sessions/{sessionId}/blocks", sessionY).with(token)
                        .contentType(MediaType.APPLICATION_JSON).content("""
                        {"id":"%s","blockName":"Moved","blockType":"TECHNIQUE"}
                        """.formatted(blockId)))
                .andExpect(status().isConflict());

        mvc.perform(get("/api/blocks/{id}", blockId).with(token))
                .andExpect(jsonPath("$.sessionId", is(sessionX)))
                .andExpect(jsonPath("$.blockName", is("Original")));
    }

    @Test
    void reSendingANoteUnderAnotherSessionIsAConflict() throws Exception {
        String athleteId = athlete("Noted");
        String sessionX = session("X");
        String sessionY = session("Y");
        String blockInY = postJson("/api/sessions/{sessionId}/blocks", """
                {"blockName":"Y block","blockType":"TECHNIQUE"}
                """, sessionY);
        String noteId = UUID.randomUUID().toString();
        postJson("/api/sessions/{sessionId}/notes", """
                {"id":"%s","athleteId":"%s","noteText":"Original"}
                """.formatted(noteId, athleteId), sessionX);

        // Before the guard this updated the note but anchored it to a block in session Y.
        mvc.perform(post("/api/sessions/{sessionId}/notes", sessionY).with(token)
                        .contentType(MediaType.APPLICATION_JSON).content("""
                        {"id":"%s","athleteId":"%s","noteText":"Moved","sessionBlockId":"%s"}
                        """.formatted(noteId, athleteId, blockInY)))
                .andExpect(status().isConflict());

        mvc.perform(get("/api/sessions/{sessionId}/notes", sessionX).with(token))
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].noteText", is("Original")))
                .andExpect(jsonPath("$[0].sessionBlockId").doesNotExist());
    }

    // --- Completed is terminal ------------------------------------------------------------------

    @Test
    void aCompletedSessionCannotBeReopenedToDeleteIt() throws Exception {
        String sessionId = session("Done");
        mvc.perform(patch("/api/sessions/{id}/status", sessionId).with(token).param("value", "COMPLETED"))
                .andExpect(status().isOk());

        // A full edit still applies its other fields, but the status stays COMPLETED...
        mvc.perform(put("/api/sessions/{id}", sessionId).with(token).contentType(MediaType.APPLICATION_JSON)
                        .content("""
                        {"sessionName":"Renamed","scheduledDate":"2026-06-01","status":"OPEN"}
                        """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.sessionName", is("Renamed")))
                .andExpect(jsonPath("$.status", is("COMPLETED")));
        // ...the explicit status endpoint refuses outright...
        mvc.perform(patch("/api/sessions/{id}/status", sessionId).with(token).param("value", "OPEN"))
                .andExpect(status().isConflict());
        // ...so the delete guard still holds.
        mvc.perform(delete("/api/sessions/{id}", sessionId).with(token))
                .andExpect(status().isConflict());
    }
}
