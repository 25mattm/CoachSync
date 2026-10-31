package com.coachsync.web;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.AthleteNote;
import com.coachsync.domain.AttendanceRecord;
import com.coachsync.domain.CoachSession;
import com.coachsync.domain.PerformanceRecord;
import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.enums.AttendanceStatus;
import com.coachsync.domain.enums.BlockType;
import com.coachsync.repository.AthleteNoteRepository;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.AttendanceRecordRepository;
import com.coachsync.repository.CoachSessionRepository;
import com.coachsync.repository.PerformanceRecordRepository;
import com.coachsync.repository.SessionBlockRepository;
import com.jayway.jsonpath.JsonPath;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
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
import static org.hamcrest.Matchers.hasSize;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@WithMockUser
@Transactional
class BlockControllerTest {

    @Autowired private MockMvc mvc;
    @PersistenceContext private EntityManager em;
    @Autowired private AthleteRepository athletes;
    @Autowired private CoachSessionRepository sessions;
    @Autowired private AttendanceRecordRepository attendance;
    @Autowired private PerformanceRecordRepository performance;
    @Autowired private AthleteNoteRepository notes;
    @Autowired private SessionBlockRepository blocks;

    private CoachSession newSession() {
        CoachSession s = new CoachSession();
        s.setSessionName("Practice");
        s.setScheduledDate(LocalDate.of(2026, 6, 16));
        return sessions.save(s);
    }

    private Athlete newAthlete(String first) {
        Athlete a = new Athlete();
        a.setFirstName(first);
        a.setLastName("Test");
        a.setDateOfBirth(LocalDate.of(2014, 1, 1));
        return athletes.save(a);
    }

    private void markPresent(CoachSession session, Athlete athlete) {
        AttendanceRecord att = new AttendanceRecord();
        att.setSession(session);
        att.setAthlete(athlete);
        att.setStatus(AttendanceStatus.PRESENT);
        attendance.save(att);
    }

    private String createBlock(UUID sessionId, String json) throws Exception {
        String body = mvc.perform(post("/api/sessions/{sid}/blocks", sessionId)
                        .contentType(MediaType.APPLICATION_JSON).content(json))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", containsString("/api/blocks/")))
                .andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.id");
    }

    @Test
    void createGeneratesSlotsForPresentAthletes() throws Exception {
        CoachSession session = newSession();
        Athlete athlete = newAthlete("Ada");
        markPresent(session, athlete);

        String blockId = createBlock(session.getId(),
                "{\"blockName\":\"8x200\",\"blockType\":\"PADDLE_DISTANCE\",\"repetitionCount\":3}");

        assertEquals(3, performance.findBySessionBlockId(UUID.fromString(blockId)).size());
    }

    @Test
    void nonCapturingBlockGeneratesNoSlots() throws Exception {
        CoachSession session = newSession();
        markPresent(session, newAthlete("Mo"));

        String blockId = createBlock(session.getId(),
                "{\"blockName\":\"Core\",\"blockType\":\"CORE\"}");

        assertTrue(performance.findBySessionBlockId(UUID.fromString(blockId)).isEmpty());
    }

    @Test
    void updateShrinkReconcilesSlots() throws Exception {
        CoachSession session = newSession();
        Athlete athlete = newAthlete("Lee");
        markPresent(session, athlete);
        String blockId = createBlock(session.getId(),
                "{\"blockName\":\"8x200\",\"blockType\":\"PADDLE_DISTANCE\",\"repetitionCount\":3}");

        mvc.perform(put("/api/blocks/{id}", blockId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"blockName\":\"8x200\",\"blockType\":\"PADDLE_DISTANCE\",\"repetitionCount\":2}"))
                .andExpect(status().isOk());

        assertEquals(2, performance.findBySessionBlockId(UUID.fromString(blockId)).size());
    }

    @Test
    void editGuardRefusesStrandingFilledResults() throws Exception {
        CoachSession session = newSession();
        Athlete athlete = newAthlete("Kai");
        markPresent(session, athlete);
        String blockId = createBlock(session.getId(),
                "{\"blockName\":\"8x200\",\"blockType\":\"PADDLE_DISTANCE\",\"repetitionCount\":3}");

        PerformanceRecord rep3 = performance.findBySessionBlockIdAndAthleteIdAndRepNumber(
                UUID.fromString(blockId), athlete.getId(), 3).orElseThrow();
        rep3.setRecordedTimeMs(54000);
        performance.save(rep3);

        mvc.perform(put("/api/blocks/{id}", blockId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"blockName\":\"8x200\",\"blockType\":\"PADDLE_DISTANCE\",\"repetitionCount\":2}"))
                .andExpect(status().isConflict());
    }

    @Test
    void deletesBlockWithoutResults() throws Exception {
        CoachSession session = newSession();
        Athlete athlete = newAthlete("Sam");
        markPresent(session, athlete);
        String blockId = createBlock(session.getId(),
                "{\"blockName\":\"8x200\",\"blockType\":\"PADDLE_DISTANCE\",\"repetitionCount\":2}");

        // Reload fresh so the block's lazy slot collection cascade-deletes.
        em.flush();
        em.clear();

        mvc.perform(delete("/api/blocks/{id}", blockId)).andExpect(status().isNoContent());
        assertTrue(performance.findBySessionBlockId(UUID.fromString(blockId)).isEmpty());
    }

    @Test
    void cannotDeleteBlockWithResults() throws Exception {
        CoachSession session = newSession();
        Athlete athlete = newAthlete("Ola");
        markPresent(session, athlete);
        String blockId = createBlock(session.getId(),
                "{\"blockName\":\"1x500\",\"blockType\":\"PADDLE_DISTANCE\",\"repetitionCount\":1}");

        PerformanceRecord rep1 = performance.findBySessionBlockIdAndAthleteIdAndRepNumber(
                UUID.fromString(blockId), athlete.getId(), 1).orElseThrow();
        rep1.setRecordedTimeMs(120000);
        performance.save(rep1);

        mvc.perform(delete("/api/blocks/{id}", blockId)).andExpect(status().isConflict());
    }

    @Test
    void deletingBlockPreservesAnchoredNotes() throws Exception {
        CoachSession session = newSession();
        Athlete athlete = newAthlete("Nia");
        String blockId = createBlock(session.getId(),
                "{\"blockName\":\"Catch drill\",\"blockType\":\"TECHNIQUE\"}");

        // A coaching note anchored to the block. The block anchor is optional; the
        // note is recorded history owned by the athlete/session and must survive the
        // block delete (and keep the athlete locked against deletion).
        AthleteNote note = new AthleteNote();
        note.setSession(session);
        note.setAthlete(athlete);
        note.setNoteText("Strong left-side catch.");
        note.setSessionBlock(em.find(SessionBlock.class, UUID.fromString(blockId)));
        UUID noteId = notes.save(note).getId();

        em.flush();
        em.clear();

        mvc.perform(delete("/api/blocks/{id}", blockId)).andExpect(status().isNoContent());

        em.flush();
        em.clear();

        AthleteNote survivor = notes.findById(noteId).orElseThrow();
        assertNull(survivor.getSessionBlock(), "block anchor should be nulled, not the note deleted");
        assertTrue(notes.existsByAthleteId(athlete.getId()), "athlete must stay locked by surviving note");
    }

    @Test
    void listsBlocksForSession() throws Exception {
        CoachSession session = newSession();
        createBlock(session.getId(), "{\"blockName\":\"A\",\"blockType\":\"CORE\"}");
        createBlock(session.getId(), "{\"blockName\":\"B\",\"blockType\":\"TECHNIQUE\"}");

        mvc.perform(get("/api/sessions/{sid}/blocks", session.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)));
    }

    @Test
    void createForUnknownSessionReturns404() throws Exception {
        mvc.perform(post("/api/sessions/{sid}/blocks", UUID.randomUUID())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"blockName\":\"X\",\"blockType\":\"CORE\"}"))
                .andExpect(status().isNotFound());
    }

    @Test
    void blankBlockNameReturns400() throws Exception {
        CoachSession session = newSession();
        mvc.perform(post("/api/sessions/{sid}/blocks", session.getId())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"blockName\":\"\",\"blockType\":\"PADDLE_DISTANCE\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors.blockName").exists());
    }

    /** A block already in the database over the limit, as saved before the limit existed. */
    private SessionBlock oversizedBlock(CoachSession session) {
        SessionBlock block = new SessionBlock();
        block.setSession(session);
        block.setBlockName("Typo");
        block.setBlockType(BlockType.PADDLE_DISTANCE);
        block.setRepetitionCount(SessionBlock.MAX_REPETITION_COUNT + 1);
        return blocks.save(block);
    }

    private void assertBlockRejected(UUID sessionId, String field, String json) throws Exception {
        mvc.perform(post("/api/sessions/{sid}/blocks", sessionId)
                        .contentType(MediaType.APPLICATION_JSON).content(json))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors['" + field + "']").exists());
    }

    @Test
    void acceptsBlockAtEveryLimit() throws Exception {
        CoachSession session = newSession();
        String pattern = "3600,".repeat(SessionBlock.MAX_PATTERN_LENGTH - 1) + "3600";

        createBlock(session.getId(), "{\"blockName\":\"Pyramid\",\"blockType\":\"PADDLE_PYRAMID\","
                + "\"repetitionCount\":500,\"setCount\":10,\"prescribedRepDurationsSec\":[" + pattern + "]}");
    }

    @Test
    void repetitionCountAboveLimitReturns400AndStoresNothing() throws Exception {
        CoachSession session = newSession();
        markPresent(session, newAthlete("Ivy"));

        assertBlockRejected(session.getId(), "repetitionCount",
                "{\"blockName\":\"Typo\",\"blockType\":\"PADDLE_DISTANCE\",\"repetitionCount\":2000000000}");
        assertBlockRejected(session.getId(), "repetitionCount",
                "{\"blockName\":\"Typo\",\"blockType\":\"PADDLE_DISTANCE\",\"repetitionCount\":501}");

        assertTrue(blocks.findBySessionIdOrderBySortOrderAsc(session.getId()).isEmpty());
    }

    @Test
    void updateCannotRaiseRepetitionCountAboveLimit() throws Exception {
        CoachSession session = newSession();
        String blockId = createBlock(session.getId(),
                "{\"blockName\":\"8x200\",\"blockType\":\"PADDLE_DISTANCE\",\"repetitionCount\":3}");

        mvc.perform(put("/api/blocks/{id}", blockId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"blockName\":\"8x200\",\"blockType\":\"PADDLE_DISTANCE\",\"repetitionCount\":501}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void setCountAboveLimitReturns400() throws Exception {
        assertBlockRejected(newSession().getId(), "setCount",
                "{\"blockName\":\"Pyramid\",\"blockType\":\"PADDLE_PYRAMID\",\"setCount\":11}");
    }

    @Test
    void patternLongerThanLimitReturns400() throws Exception {
        String pattern = "60,".repeat(SessionBlock.MAX_PATTERN_LENGTH) + "60";
        assertBlockRejected(newSession().getId(), "prescribedRepDurationsSec",
                "{\"blockName\":\"Pyramid\",\"blockType\":\"PADDLE_PYRAMID\","
                        + "\"prescribedRepDurationsSec\":[" + pattern + "]}");
    }

    @Test
    void patternDurationsAreValidated() throws Exception {
        UUID sessionId = newSession().getId();
        for (String bad : new String[]{"0", "-60", "3601", "null"}) {
            assertBlockRejected(sessionId, "prescribedRepDurationsSec[1]",
                    "{\"blockName\":\"Pyramid\",\"blockType\":\"PADDLE_PYRAMID\","
                            + "\"prescribedRepDurationsSec\":[60," + bad + "]}");
        }
    }

    @Test
    void anExistingOversizedBlockDoesNotReconcileOrBlockTheSession() throws Exception {
        CoachSession session = newSession();
        Athlete athlete = newAthlete("Rae");
        SessionBlock oversized = oversizedBlock(session);
        String normal = createBlock(session.getId(),
                "{\"blockName\":\"4x200\",\"blockType\":\"PADDLE_DISTANCE\",\"repetitionCount\":4,\"sortOrder\":1}");

        mvc.perform(put("/api/sessions/{sid}/attendance", session.getId())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"entries\":[{\"athleteId\":\"" + athlete.getId() + "\",\"status\":\"PRESENT\"}]}"))
                .andExpect(status().isOk());

        assertTrue(performance.findBySessionBlockId(oversized.getId()).isEmpty());
        assertEquals(4, performance.findBySessionBlockId(UUID.fromString(normal)).size(),
                "the session's other blocks still get their slots");
    }

    @Test
    void anExistingOversizedBlockCanBeLoweredAndThenGetsItsSlots() throws Exception {
        CoachSession session = newSession();
        markPresent(session, newAthlete("Zed"));
        SessionBlock oversized = oversizedBlock(session);

        mvc.perform(put("/api/blocks/{id}", oversized.getId()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"blockName\":\"Fixed\",\"blockType\":\"PADDLE_DISTANCE\",\"repetitionCount\":3}"))
                .andExpect(status().isOk());

        assertEquals(3, performance.findBySessionBlockId(oversized.getId()).size());
    }

    @Test
    void anExistingOversizedBlockCanBeDeleted() throws Exception {
        CoachSession session = newSession();
        SessionBlock oversized = oversizedBlock(session);

        em.flush();
        em.clear();

        mvc.perform(delete("/api/blocks/{id}", oversized.getId())).andExpect(status().isNoContent());
        assertTrue(blocks.findById(oversized.getId()).isEmpty());
    }
}
