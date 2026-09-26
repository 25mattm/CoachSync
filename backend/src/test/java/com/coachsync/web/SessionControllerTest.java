package com.coachsync.web;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.AttendanceRecord;
import com.coachsync.domain.CoachSession;
import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.enums.BlockType;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.AttendanceRecordRepository;
import com.coachsync.repository.CoachSessionRepository;
import com.coachsync.repository.SessionBlockRepository;
import com.coachsync.web.ClubFixtures.ClubFixture;
import com.jayway.jsonpath.JsonPath;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
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

import java.time.LocalDate;
import java.util.UUID;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@WithMockUser
@Transactional
@Import(ClubFixtures.class)
class SessionControllerTest {

    @Autowired private MockMvc mvc;
    @PersistenceContext private EntityManager em;
    @Autowired private ClubFixtures fixtures;
    @Autowired private AthleteRepository athletes;
    @Autowired private CoachSessionRepository sessions;
    @Autowired private SessionBlockRepository blocks;
    @Autowired private AttendanceRecordRepository attendance;

    private record CreatedSession(String id, RequestPostProcessor as) {}

    /**
     * Every subsequent call against this session must reuse {@code as} — a bare
     * {@code @WithMockUser} request (no club claim) resolves to {@code NO_TENANT} and would 404
     * against a session tenant-stamped to a real club. The club-scoped fixture coach is what makes
     * this land under a real tenant instead: {@code ClubMembershipWriteGuard} now rejects a
     * club-less caller's write to any non-bootstrap route, and even before that guard, a club-less
     * caller could never legitimately create the sessions these tests exercise.
     */
    private CreatedSession createSession(String name) throws Exception {
        return createSession(name, fixtures.token(fixtures.club()));
    }

    /** For tests that need two sessions in the same club — e.g. filtering one club's own list. */
    private CreatedSession createSession(String name, RequestPostProcessor as) throws Exception {
        String body = mvc.perform(post("/api/sessions")
                        .with(as)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"sessionName\":\"" + name + "\",\"scheduledDate\":\"2026-06-16\"}"))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", containsString("/api/sessions/")))
                .andReturn().getResponse().getContentAsString();
        return new CreatedSession(JsonPath.read(body, "$.id"), as);
    }

    private Athlete newAthlete(String first) {
        Athlete a = new Athlete();
        a.setFirstName(first);
        a.setLastName("Test");
        a.setDateOfBirth(LocalDate.of(2014, 1, 1));
        return athletes.save(a);
    }

    @Test
    void createsReadsUpdatesSession() throws Exception {
        CreatedSession created = createSession("Tuesday AM");
        mvc.perform(get("/api/sessions/{id}", created.id()).with(created.as()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.sessionName", is("Tuesday AM")))
                .andExpect(jsonPath("$.status", is("OPEN")))
                .andExpect(jsonPath("$.archived", is(false)));
        mvc.perform(put("/api/sessions/{id}", created.id()).with(created.as())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"sessionName\":\"Tuesday PM\",\"scheduledDate\":\"2026-06-17\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.sessionName", is("Tuesday PM")));
    }

    @Test
    void createStampsAuthenticatedCoachAndResolvesTeam() throws Exception {
        ClubFixture f = fixtures.club();
        RequestPostProcessor as = fixtures.token(f);
        // The team must be created under the same tenant as the session — a team stamped to a
        // different club (or NO_TENANT, if created via a direct repository save under the class's
        // ambient @WithMockUser) would be invisible to this club-scoped request's own tenant filter,
        // same as any other cross-club lookup.
        String teamBody = mvc.perform(post("/api/teams").with(as)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"teamName\":\"U14\"}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        String teamId = JsonPath.read(teamBody, "$.id");

        // The "logged by" coach comes from the authenticated principal, not the body.
        mvc.perform(post("/api/sessions")
                        .with(as)
                        .contentType(MediaType.APPLICATION_JSON).content(
                        "{\"sessionName\":\"WithRefs\",\"scheduledDate\":\"2026-06-16\",\"teamId\":\""
                                + teamId + "\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.coachId", is(f.coachId().toString())))
                .andExpect(jsonPath("$.teamId", is(teamId)));
    }

    @Test
    void createWithUnknownPrincipalCoachReturns401() throws Exception {
        // A token whose subject isn't a real coach (e.g. since-deleted) is rejected up front by
        // ActiveCoachFilter — the per-request revocation guard — before it reaches the controller.
        mvc.perform(post("/api/sessions")
                        .with(jwt().jwt(j -> j.subject(UUID.randomUUID().toString())))
                        .contentType(MediaType.APPLICATION_JSON).content(
                        "{\"sessionName\":\"X\",\"scheduledDate\":\"2026-06-16\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void blankNameReturns400() throws Exception {
        mvc.perform(post("/api/sessions").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"sessionName\":\"\",\"scheduledDate\":\"2026-06-16\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors.sessionName").exists());
    }

    @Test
    void statusAndArchiveTransitions() throws Exception {
        CreatedSession created = createSession("Lifecycle");
        mvc.perform(patch("/api/sessions/{id}/status", created.id()).with(created.as()).param("value", "COMPLETED"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status", is("COMPLETED")));
        mvc.perform(patch("/api/sessions/{id}/archive", created.id()).with(created.as()).param("value", "true"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.archived", is(true)));
    }

    @Test
    void listFiltersByStatus() throws Exception {
        // Both sessions must be in the SAME club: this proves the status filter excludes the
        // cancelled one, not merely that tenant isolation hides a different club's session.
        RequestPostProcessor as = fixtures.token(fixtures.club());
        CreatedSession openOne = createSession("OpenOne", as);
        CreatedSession other = createSession("CancelledOne", as);
        mvc.perform(patch("/api/sessions/{id}/status", other.id()).with(as).param("value", "CANCELLED"));

        mvc.perform(get("/api/sessions").with(as).param("status", "OPEN"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content", hasSize(1)))
                .andExpect(jsonPath("$.content[0].sessionName", is("OpenOne")));
    }

    @Test
    void deletesOpenSession() throws Exception {
        CreatedSession created = createSession("Throwaway");
        mvc.perform(delete("/api/sessions/{id}", created.id()).with(created.as())).andExpect(status().isNoContent());
        mvc.perform(get("/api/sessions/{id}", created.id()).with(created.as())).andExpect(status().isNotFound());
    }

    @Test
    void cannotDeleteCompletedSession() throws Exception {
        CreatedSession created = createSession("Done");
        mvc.perform(patch("/api/sessions/{id}/status", created.id()).with(created.as()).param("value", "COMPLETED"))
                .andExpect(status().isOk());
        mvc.perform(delete("/api/sessions/{id}", created.id()).with(created.as())).andExpect(status().isConflict());
    }

    @Test
    void putAppliesStatusAndArchived() throws Exception {
        // Full-state sync PUT carries status + archived (which the LWW push relies on, since
        // routing them through the PATCH endpoints would stamp server-time updatedAt).
        CreatedSession created = createSession("Toggle");
        mvc.perform(put("/api/sessions/{id}", created.id()).with(created.as())
                        .contentType(MediaType.APPLICATION_JSON).content(
                        "{\"sessionName\":\"Toggle\",\"scheduledDate\":\"2026-06-16\","
                                + "\"status\":\"COMPLETED\",\"archived\":true}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status", is("COMPLETED")))
                .andExpect(jsonPath("$.archived", is(true)));
    }

    @Test
    void deleteCascadesBlocksAndAttendance() throws Exception {
        CoachSession session = new CoachSession();
        session.setSessionName("Cascade");
        session.setScheduledDate(LocalDate.of(2026, 6, 16));
        session = sessions.save(session);
        Athlete athlete = newAthlete("Cas");

        SessionBlock block = new SessionBlock();
        block.setBlockName("Paddle");
        block.setBlockType(BlockType.PADDLE_DISTANCE);
        block.setSession(session);
        blocks.save(block);

        AttendanceRecord att = new AttendanceRecord();
        att.setSession(session);
        att.setAthlete(athlete);
        attendance.save(att);

        UUID sessionId = session.getId();
        em.flush();
        em.clear();

        mvc.perform(delete("/api/sessions/{id}", sessionId)).andExpect(status().isNoContent());

        assertTrue(sessions.findById(sessionId).isEmpty(), "session should be deleted");
        assertTrue(blocks.findBySessionIdOrderBySortOrderAsc(sessionId).isEmpty(), "blocks should cascade");
        assertTrue(attendance.findBySessionId(sessionId).isEmpty(), "attendance should cascade");
    }
}
