package com.coachsync.web;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.CoachSession;
import com.coachsync.domain.PerformanceRecord;
import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.enums.BlockType;
import com.coachsync.domain.enums.RepEntryStatus;
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
import static org.hamcrest.Matchers.nullValue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@WithMockUser
@Transactional
class PerformanceControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private AthleteRepository athletes;
    @Autowired private CoachSessionRepository sessions;
    @Autowired private SessionBlockRepository blocks;
    @Autowired private PerformanceRecordRepository performance;

    private SessionBlock block;
    private PerformanceRecord slot1;
    private Athlete athlete;

    private void setUp() {
        CoachSession session = new CoachSession();
        session.setSessionName("Practice");
        session.setScheduledDate(LocalDate.of(2026, 6, 16));
        session = sessions.save(session);

        block = new SessionBlock();
        block.setBlockName("2x500");
        block.setBlockType(BlockType.PADDLE_DISTANCE);
        block.setRepetitionCount(2);
        block.setSession(session);
        block = blocks.save(block);

        athlete = new Athlete();
        athlete.setFirstName("Ada");
        athlete.setLastName("Paddle");
        athlete.setDateOfBirth(LocalDate.of(2014, 1, 1));
        athlete = athletes.save(athlete);

        slot1 = newSlot(athlete, 1);
        newSlot(athlete, 2);
    }

    private PerformanceRecord newSlot(Athlete athlete, int rep) {
        PerformanceRecord slot = new PerformanceRecord();
        slot.setSessionBlock(block);
        slot.setAthlete(athlete);
        slot.setRepNumber(rep);
        slot.setStatus(RepEntryStatus.PENDING);
        return performance.save(slot);
    }

    @Test
    void listsBlockSlotsInRepOrder() throws Exception {
        setUp();
        mvc.perform(get("/api/blocks/{id}/performance", block.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)))
                .andExpect(jsonPath("$[0].repNumber", is(1)))
                .andExpect(jsonPath("$[0].status", is("PENDING")));
    }

    @Test
    void recordsTimeAsComplete() throws Exception {
        setUp();
        mvc.perform(put("/api/performance/{id}", slot1.getId()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"recordedTimeMs\":54210,\"status\":\"COMPLETE\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status", is("COMPLETE")))
                .andExpect(jsonPath("$.recordedTimeMs", is(54210)));
    }

    @Test
    void recordsDnsAndClearsTime() throws Exception {
        setUp();
        mvc.perform(put("/api/performance/{id}", slot1.getId()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"recordedTimeMs\":99999,\"status\":\"DNS\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status", is("DNS")))
                .andExpect(jsonPath("$.recordedTimeMs", is(nullValue())));
    }

    @Test
    void completeWithoutTimeReturns400() throws Exception {
        setUp();
        mvc.perform(put("/api/performance/{id}", slot1.getId()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"status\":\"COMPLETE\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void completeWithZeroTimeReturns400() throws Exception {
        setUp();
        // 0 passes the DTO's @PositiveOrZero, so the service guard must reject it:
        // a 0 ms rep is not a real result.
        mvc.perform(put("/api/performance/{id}", slot1.getId()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"recordedTimeMs\":0,\"status\":\"COMPLETE\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void recordUnknownReturns404() throws Exception {
        mvc.perform(put("/api/performance/{id}", UUID.randomUUID()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"recordedTimeMs\":1000,\"status\":\"COMPLETE\"}"))
                .andExpect(status().isNotFound());
    }

    @Test
    void naturalKeyUpsertMatchesExistingSlotByBlockAthleteRep() throws Exception {
        setUp();
        // Future updatedAt (the PENDING slots were stamped at insert ≈ now), so the write wins.
        // Matching by (block, athlete, rep) must UPDATE rep 1's slot — not create a third.
        mvc.perform(put("/api/blocks/{blockId}/performance", block.getId())
                        .contentType(MediaType.APPLICATION_JSON).content(
                        "{\"entries\":[{\"athleteId\":\"" + athlete.getId() + "\",\"repNumber\":1,"
                                + "\"status\":\"COMPLETE\",\"recordedTimeMs\":54210,"
                                + "\"updatedAt\":\"2030-01-01T00:00:00Z\"}]}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)))
                .andExpect(jsonPath("$[0].repNumber", is(1)))
                .andExpect(jsonPath("$[0].status", is("COMPLETE")))
                .andExpect(jsonPath("$[0].recordedTimeMs", is(54210)));
    }

    @Test
    void naturalKeyUpsertSkipsStale() throws Exception {
        setUp();
        String prefix = "{\"entries\":[{\"athleteId\":\"" + athlete.getId() + "\",\"repNumber\":1,";
        mvc.perform(put("/api/blocks/{blockId}/performance", block.getId()).contentType(MediaType.APPLICATION_JSON)
                        .content(prefix + "\"status\":\"COMPLETE\",\"recordedTimeMs\":50000,"
                                + "\"updatedAt\":\"2030-01-01T00:00:00Z\"}]}"))
                .andExpect(status().isOk());
        // An older write is ignored (last-write-wins) — but only because the slot now holds a result.
        mvc.perform(put("/api/blocks/{blockId}/performance", block.getId()).contentType(MediaType.APPLICATION_JSON)
                        .content(prefix + "\"status\":\"DNF\",\"updatedAt\":\"2020-01-01T00:00:00Z\"}]}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].status", is("COMPLETE")))
                .andExpect(jsonPath("$[0].recordedTimeMs", is(50000)));
    }

    @Test
    void olderResultStillFillsAPendingPlaceholder() throws Exception {
        setUp();   // PENDING slots are stamped ~now by @PrePersist (server time)
        // A reconcile-created PENDING slot carries a server timestamp newer than an offline-entered
        // result. Skip-stale must NOT drop the real result onto a placeholder, or the rep time is lost.
        mvc.perform(put("/api/blocks/{blockId}/performance", block.getId())
                        .contentType(MediaType.APPLICATION_JSON).content(
                        "{\"entries\":[{\"athleteId\":\"" + athlete.getId() + "\",\"repNumber\":1,"
                                + "\"status\":\"COMPLETE\",\"recordedTimeMs\":54210,"
                                + "\"updatedAt\":\"2020-01-01T00:00:00Z\"}]}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].status", is("COMPLETE")))
                .andExpect(jsonPath("$[0].recordedTimeMs", is(54210)));
    }
}
