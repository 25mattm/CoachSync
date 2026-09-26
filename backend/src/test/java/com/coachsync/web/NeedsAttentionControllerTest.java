package com.coachsync.web;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.CoachSession;
import com.coachsync.domain.PerformanceRecord;
import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.enums.BlockType;
import com.coachsync.domain.enums.RepEntryStatus;
import com.coachsync.domain.enums.SessionStatus;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.CoachSessionRepository;
import com.coachsync.repository.PerformanceRecordRepository;
import com.coachsync.repository.SessionBlockRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@WithMockUser
@Transactional
class NeedsAttentionControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private AthleteRepository athletes;
    @Autowired private CoachSessionRepository sessions;
    @Autowired private SessionBlockRepository blocks;
    @Autowired private PerformanceRecordRepository performance;

    private Athlete athlete(String first, String last, boolean active) {
        Athlete a = new Athlete();
        a.setFirstName(first);
        a.setLastName(last);
        a.setDateOfBirth(LocalDate.of(2012, 1, 1));
        a.setActive(active);
        return athletes.save(a);
    }

    /** Three sessions of one block, one rep each; times follow {@code times}. */
    private void blockTrend(Athlete a, String blockName, int[] times) {
        for (int i = 0; i < times.length; i++) {
            CoachSession s = new CoachSession();
            s.setSessionName("Practice");
            s.setScheduledDate(LocalDate.now().minusDays((times.length - i) * 10L));
            s.setStatus(SessionStatus.COMPLETED);
            s = sessions.save(s);

            SessionBlock b = new SessionBlock();
            b.setSession(s);
            b.setBlockName(blockName);
            b.setBlockType(BlockType.PADDLE_DISTANCE);
            b = blocks.save(b);

            PerformanceRecord r = new PerformanceRecord();
            r.setSessionBlock(b);
            r.setAthlete(a);
            r.setRepNumber(1);
            r.setStatus(RepEntryStatus.COMPLETE);
            r.setRecordedTimeMs(times[i]);
            performance.save(r);
        }
    }

    @Test
    void listsActiveAthletesWithNegativeSignalsOnly() throws Exception {
        Athlete declining = athlete("Zed", "Declining", true);
        blockTrend(declining, "Sprints", new int[]{50000, 60000, 70000});   // slope up -> declining
        Athlete improving = athlete("Amy", "Improving", true);
        blockTrend(improving, "Endurance", new int[]{70000, 60000, 50000}); // slope down -> positive, excluded
        Athlete inactive = athlete("Ina", "Inactive", false);
        blockTrend(inactive, "Sprints", new int[]{50000, 60000, 70000});    // declining but inactive, excluded

        mvc.perform(get("/api/analytics/needs-attention"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].lastName", is("Declining")))
                .andExpect(jsonPath("$[0].decliningBlock", is("Sprints")))
                .andExpect(jsonPath("$[0].inconsistentPacing").isEmpty());
    }

    @Test
    void emptyWhenNoNegativeSignals() throws Exception {
        Athlete a = athlete("Bo", "Fine", true);
        blockTrend(a, "Steady", new int[]{60000, 60000, 60000}); // flat slope, no CV -> no signal

        mvc.perform(get("/api/analytics/needs-attention"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(0)));
    }
}
