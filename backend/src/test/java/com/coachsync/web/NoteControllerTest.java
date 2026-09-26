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
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * A note (and the session/athlete it's created under) must all be created under the SAME real
 * club-scoped fixture coach — direct repository saves under the class's ambient
 * {@code @WithMockUser} would stamp {@code NO_TENANT}, invisible to a request authenticated with a
 * real club claim. Every setup entity below is therefore created through the real HTTP API with a
 * fixture coach's token, not via a direct repository save.
 */
@SpringBootTest
@AutoConfigureMockMvc
@WithMockUser
@Transactional
@Import(ClubFixtures.class)
class NoteControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private ClubFixtures fixtures;

    private UUID newSession(RequestPostProcessor as) throws Exception {
        String body = mvc.perform(post("/api/sessions").with(as)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"sessionName\":\"Practice\",\"scheduledDate\":\"2026-06-16\"}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return UUID.fromString(JsonPath.read(body, "$.id"));
    }

    private UUID newAthlete(RequestPostProcessor as) throws Exception {
        String body = mvc.perform(post("/api/athletes").with(as)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"firstName\":\"Ada\",\"lastName\":\"Paddle\",\"dateOfBirth\":\"2014-01-01\"}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return UUID.fromString(JsonPath.read(body, "$.id"));
    }

    private UUID newBlock(RequestPostProcessor as, UUID sessionId) throws Exception {
        String body = mvc.perform(post("/api/sessions/{sid}/blocks", sessionId).with(as)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"blockName\":\"Core\",\"blockType\":\"CORE\"}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return UUID.fromString(JsonPath.read(body, "$.id"));
    }

    private String createNote(RequestPostProcessor as, UUID sessionId, UUID athleteId) throws Exception {
        String body = mvc.perform(post("/api/sessions/{sid}/notes", sessionId)
                        .with(as)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"athleteId\":\"" + athleteId + "\",\"noteText\":\"Strong catch\"}"))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", containsString("/api/notes/")))
                .andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.id");
    }

    @Test
    void createsNoteForSession() throws Exception {
        RequestPostProcessor as = fixtures.token(fixtures.club());
        UUID sessionId = newSession(as);
        UUID athleteId = newAthlete(as);

        mvc.perform(post("/api/sessions/{sid}/notes", sessionId)
                        .with(as)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"athleteId\":\"" + athleteId + "\",\"noteText\":\"Strong catch\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.athleteId", is(athleteId.toString())))
                .andExpect(jsonPath("$.sessionId", is(sessionId.toString())))
                .andExpect(jsonPath("$.noteText", is("Strong catch")))
                .andExpect(jsonPath("$.athleteFirstName", is("Ada")));
    }

    @Test
    void createsNoteAnchoredToBlockStampingAuthenticatedCoach() throws Exception {
        ClubFixture f = fixtures.club();
        RequestPostProcessor as = fixtures.token(f);
        UUID sessionId = newSession(as);
        UUID athleteId = newAthlete(as);
        UUID blockId = newBlock(as, sessionId);

        // Block anchor comes from the body; the "logged by" coach from the principal.
        mvc.perform(post("/api/sessions/{sid}/notes", sessionId)
                        .with(as)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"athleteId\":\"" + athleteId + "\",\"noteText\":\"Hips\",\"sessionBlockId\":\""
                                + blockId + "\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.sessionBlockId", is(blockId.toString())))
                .andExpect(jsonPath("$.coachId", is(f.coachId().toString())));
    }

    @Test
    void blockFromAnotherSessionReturns400() throws Exception {
        RequestPostProcessor as = fixtures.token(fixtures.club());
        UUID session = newSession(as);
        UUID other = newSession(as);
        UUID athleteId = newAthlete(as);
        UUID blockId = newBlock(as, other);

        mvc.perform(post("/api/sessions/{sid}/notes", session)
                        .with(as)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"athleteId\":\"" + athleteId + "\",\"noteText\":\"x\",\"sessionBlockId\":\""
                                + blockId + "\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void listsNotesByAthleteAndSession() throws Exception {
        RequestPostProcessor as = fixtures.token(fixtures.club());
        UUID sessionId = newSession(as);
        UUID athleteId = newAthlete(as);
        createNote(as, sessionId, athleteId);

        mvc.perform(get("/api/athletes/{id}/notes", athleteId).with(as))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)));
        mvc.perform(get("/api/sessions/{id}/notes", sessionId).with(as))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)));
    }

    @Test
    void updatesNote() throws Exception {
        RequestPostProcessor as = fixtures.token(fixtures.club());
        UUID sessionId = newSession(as);
        UUID athleteId = newAthlete(as);
        String id = createNote(as, sessionId, athleteId);

        mvc.perform(put("/api/notes/{id}", id).with(as).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"noteText\":\"Updated note\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.noteText", is("Updated note")));
    }

    @Test
    void deletesNote() throws Exception {
        RequestPostProcessor as = fixtures.token(fixtures.club());
        UUID sessionId = newSession(as);
        UUID athleteId = newAthlete(as);
        String id = createNote(as, sessionId, athleteId);

        mvc.perform(delete("/api/notes/{id}", id).with(as)).andExpect(status().isNoContent());
        mvc.perform(get("/api/sessions/{id}/notes", sessionId).with(as))
                .andExpect(jsonPath("$", hasSize(0)));
    }

    @Test
    void unknownAthleteReturns404() throws Exception {
        RequestPostProcessor as = fixtures.token(fixtures.club());
        UUID sessionId = newSession(as);
        // A real coach principal (so ActiveCoachFilter passes) but a non-existent athlete.
        mvc.perform(post("/api/sessions/{sid}/notes", sessionId)
                        .with(as)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"athleteId\":\"" + UUID.randomUUID() + "\",\"noteText\":\"x\"}"))
                .andExpect(status().isNotFound());
    }

    @Test
    void blankNoteTextReturns400() throws Exception {
        // @Valid rejects a blank noteText before the controller body runs, so neither the session nor
        // the athlete id needs to resolve to a real row — bare random UUIDs prove the same thing
        // without the DB/HTTP round trips a real fixture would cost. Also deliberately not club-scoped
        // (no .with(as)), to prove validation fires regardless.
        mvc.perform(post("/api/sessions/{sid}/notes", UUID.randomUUID())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"athleteId\":\"" + UUID.randomUUID() + "\",\"noteText\":\"\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors.noteText").exists());
    }
}
