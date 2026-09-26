package com.coachsync.web;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.CoachSession;
import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.enums.BlockType;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.CoachSessionRepository;
import com.coachsync.repository.PerformanceRecordRepository;
import com.coachsync.repository.SessionBlockRepository;
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

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@WithMockUser
@Transactional
class AttendanceControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private AthleteRepository athletes;
    @Autowired private CoachSessionRepository sessions;
    @Autowired private SessionBlockRepository blocks;
    @Autowired private PerformanceRecordRepository performance;

    private CoachSession newSession() {
        CoachSession s = new CoachSession();
        s.setSessionName("Practice");
        s.setScheduledDate(LocalDate.of(2026, 6, 16));
        return sessions.save(s);
    }

    private SessionBlock newBlock(CoachSession session, int reps) {
        SessionBlock b = new SessionBlock();
        b.setBlockName("8x200");
        b.setBlockType(BlockType.PADDLE_DISTANCE);
        b.setRepetitionCount(reps);
        b.setSession(session);
        return blocks.save(b);
    }

    private Athlete newAthlete(String first) {
        Athlete a = new Athlete();
        a.setFirstName(first);
        a.setLastName("Test");
        a.setDateOfBirth(LocalDate.of(2014, 1, 1));
        return athletes.save(a);
    }

    private String present(UUID athleteId) {
        return "{\"entries\":[{\"athleteId\":\"" + athleteId + "\",\"status\":\"PRESENT\"}]}";
    }

    @Test
    void setAttendanceGeneratesSlotsAndLists() throws Exception {
        CoachSession session = newSession();
        SessionBlock block = newBlock(session, 2);
        Athlete athlete = newAthlete("Ada");

        mvc.perform(put("/api/sessions/{sid}/attendance", session.getId())
                        .contentType(MediaType.APPLICATION_JSON).content(present(athlete.getId())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].status", is("PRESENT")))
                .andExpect(jsonPath("$[0].athleteFirstName", is("Ada")));

        assertEquals(2, performance.findBySessionBlockId(block.getId()).size());

        mvc.perform(get("/api/sessions/{sid}/attendance", session.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)));
    }

    @Test
    void markingAbsentPrunesUnfilledSlots() throws Exception {
        CoachSession session = newSession();
        SessionBlock block = newBlock(session, 2);
        Athlete athlete = newAthlete("Mo");

        mvc.perform(put("/api/sessions/{sid}/attendance", session.getId())
                        .contentType(MediaType.APPLICATION_JSON).content(present(athlete.getId())))
                .andExpect(status().isOk());
        assertEquals(2, performance.findBySessionBlockId(block.getId()).size());

        mvc.perform(put("/api/sessions/{sid}/attendance", session.getId())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"entries\":[{\"athleteId\":\"" + athlete.getId()
                                + "\",\"status\":\"ABSENT\",\"absenceReason\":\"sick\"}]}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].status", is("ABSENT")))
                .andExpect(jsonPath("$[0].absenceReason", is("sick")));

        assertEquals(0, performance.findBySessionBlockId(block.getId()).size());
    }

    @Test
    void unknownAthleteReturns404() throws Exception {
        CoachSession session = newSession();
        mvc.perform(put("/api/sessions/{sid}/attendance", session.getId())
                        .contentType(MediaType.APPLICATION_JSON).content(present(UUID.randomUUID())))
                .andExpect(status().isNotFound());
    }

    @Test
    void unknownSessionReturns404() throws Exception {
        Athlete athlete = newAthlete("Sam");
        mvc.perform(put("/api/sessions/{sid}/attendance", UUID.randomUUID())
                        .contentType(MediaType.APPLICATION_JSON).content(present(athlete.getId())))
                .andExpect(status().isNotFound());
    }

    @Test
    void emptyEntriesReturns400() throws Exception {
        CoachSession session = newSession();
        mvc.perform(put("/api/sessions/{sid}/attendance", session.getId())
                        .contentType(MediaType.APPLICATION_JSON).content("{\"entries\":[]}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors.entries").exists());
    }
}
