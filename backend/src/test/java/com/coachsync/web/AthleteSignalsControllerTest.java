package com.coachsync.web;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.CoachSession;
import com.coachsync.domain.KtcAssessment;
import com.coachsync.domain.PerformanceRecord;
import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.enums.BlockType;
import com.coachsync.domain.enums.RepEntryStatus;
import com.coachsync.domain.enums.SessionStatus;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.CoachSessionRepository;
import com.coachsync.repository.KtcAssessmentRepository;
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
import java.util.UUID;

import static org.hamcrest.Matchers.is;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@WithMockUser
@Transactional
class AthleteSignalsControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private AthleteRepository athletes;
    @Autowired private CoachSessionRepository sessions;
    @Autowired private SessionBlockRepository blocks;
    @Autowired private PerformanceRecordRepository performance;
    @Autowired private KtcAssessmentRepository ktc;

    private Athlete newAthlete() {
        Athlete a = new Athlete();
        a.setFirstName("Ada");
        a.setLastName("Paddle");
        a.setDateOfBirth(LocalDate.of(2012, 1, 1));
        return athletes.save(a);
    }

    private CoachSession newSession(LocalDate date) {
        CoachSession s = new CoachSession();
        s.setSessionName("Practice");
        s.setScheduledDate(date);
        s.setStatus(SessionStatus.COMPLETED);
        return sessions.save(s);
    }

    private SessionBlock newBlock(CoachSession s, String name) {
        SessionBlock b = new SessionBlock();
        b.setSession(s);
        b.setBlockName(name);
        b.setBlockType(BlockType.PADDLE_DISTANCE);
        return blocks.save(b);
    }

    private void rep(SessionBlock block, Athlete a, int repNumber, int timeMs) {
        PerformanceRecord r = new PerformanceRecord();
        r.setSessionBlock(block);
        r.setAthlete(a);
        r.setRepNumber(repNumber);
        r.setStatus(RepEntryStatus.COMPLETE);
        r.setRecordedTimeMs(timeMs);
        performance.save(r);
    }

    private void ktcAssessment(Athlete a, LocalDate date, int score) {
        KtcAssessment k = new KtcAssessment();
        k.setAthlete(a);
        k.setDate(date);
        k.setWindow("General Prep 1");
        k.setSetupRecoveryScore(score);
        k.setCatchScore(score);
        k.setPropulsionDrawScore(score);
        k.setExitScore(score);
        ktc.save(k);
    }

    @Test
    void flagsDecliningAndMostImprovedBlocks() throws Exception {
        Athlete a = newAthlete();
        // Same two block names across three sessions; one rep each so pacing CV
        // never fires. Sprints times rise (declining), Endurance times fall.
        int[] sprints = {50000, 60000, 70000};
        int[] endurance = {70000, 60000, 50000};
        LocalDate[] dates = {LocalDate.now().minusDays(20), LocalDate.now().minusDays(10), LocalDate.now()};
        for (int i = 0; i < 3; i++) {
            CoachSession s = newSession(dates[i]);
            rep(newBlock(s, "Sprints"), a, 1, sprints[i]);
            rep(newBlock(s, "Endurance"), a, 1, endurance[i]);
        }

        mvc.perform(get("/api/athletes/{id}/signals", a.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.decliningBlock", is("Sprints")))
                .andExpect(jsonPath("$.mostImprovedBlock", is("Endurance")))
                .andExpect(jsonPath("$.inconsistentPacing").isEmpty());
    }

    @Test
    void flagsInconsistentPacing() throws Exception {
        Athlete a = newAthlete();
        // Two reps per session (40s, 80s -> CV = 1/3) across two sessions.
        for (LocalDate date : new LocalDate[]{LocalDate.now().minusDays(5), LocalDate.now()}) {
            SessionBlock intervals = newBlock(newSession(date), "Intervals");
            rep(intervals, a, 1, 40000);
            rep(intervals, a, 2, 80000);
        }

        mvc.perform(get("/api/athletes/{id}/signals", a.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.inconsistentPacing.blockName", is("Intervals")))
                .andExpect(jsonPath("$.inconsistentPacing.cvPercent", is(33)));
    }

    @Test
    void noSignalsWithThinData() throws Exception {
        Athlete a = newAthlete();
        // One block, one session, two equal reps: < 3 reps (no regression) and a
        // single session (CV needs >= 2 sessions) -> every signal stays null.
        SessionBlock solo = newBlock(newSession(LocalDate.now()), "Solo");
        rep(solo, a, 1, 50000);
        rep(solo, a, 2, 50000);

        mvc.perform(get("/api/athletes/{id}/signals", a.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.decliningBlock").isEmpty())
                .andExpect(jsonPath("$.mostImprovedBlock").isEmpty())
                .andExpect(jsonPath("$.inconsistentPacing").isEmpty())
                .andExpect(jsonPath("$.ktcDecliningCount").isEmpty());
    }

    @Test
    void flagsDecliningKtcTrend() throws Exception {
        Athlete a = newAthlete();
        // Three KTC assessments with a falling average score -> declining trend.
        ktcAssessment(a, LocalDate.now().minusDays(60), 5);
        ktcAssessment(a, LocalDate.now().minusDays(30), 3);
        ktcAssessment(a, LocalDate.now(), 1);

        mvc.perform(get("/api/athletes/{id}/signals", a.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.ktcDecliningCount", is(3)));
    }

    @Test
    void unknownAthleteReturns404() throws Exception {
        mvc.perform(get("/api/athletes/{id}/signals", UUID.randomUUID()))
                .andExpect(status().isNotFound());
    }
}
