package com.coachsync.web;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.AttendanceRecord;
import com.coachsync.domain.CoachSession;
import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.enums.AttendanceStatus;
import com.coachsync.domain.enums.BlockType;
import com.coachsync.domain.enums.SessionStatus;
import com.coachsync.domain.enums.TrainingZone;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.AttendanceRecordRepository;
import com.coachsync.repository.CoachSessionRepository;
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

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@WithMockUser
@Transactional
class AthleteAnalyticsControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private AthleteRepository athletes;
    @Autowired private CoachSessionRepository sessions;
    @Autowired private SessionBlockRepository blocks;
    @Autowired private AttendanceRecordRepository attendance;

    private final int year = LocalDate.now().getYear();

    private Athlete athlete(int birthYear) {
        Athlete a = new Athlete();
        a.setFirstName("Ada");
        a.setLastName("Paddle");
        a.setDateOfBirth(LocalDate.of(birthYear, 1, 1));
        return athletes.save(a);
    }

    private CoachSession session(SessionStatus statusValue) {
        CoachSession s = new CoachSession();
        s.setSessionName("Practice");
        s.setScheduledDate(LocalDate.now());
        s.setStatus(statusValue);
        return sessions.save(s);
    }

    private void addBlock(CoachSession s, BlockType type, TrainingZone zone, double km) {
        SessionBlock b = new SessionBlock();
        b.setSession(s);
        b.setBlockName(type.name());
        b.setBlockType(type);
        b.setTrainingZone(zone);
        b.setDistanceKm(km);
        blocks.save(b);
    }

    private void mark(CoachSession s, Athlete a, AttendanceStatus statusValue) {
        AttendanceRecord r = new AttendanceRecord();
        r.setSession(s);
        r.setAthlete(a);
        r.setStatus(statusValue);
        attendance.save(r);
    }

    @Test
    void computesSeasonalLoadPaddleKmAndZones() throws Exception {
        Athlete a = athlete(year - 14); // age 14 -> U14 (target 700-1530)
        CoachSession s = session(SessionStatus.COMPLETED);
        addBlock(s, BlockType.PADDLE_DISTANCE, TrainingZone.GA_1, 8.0);
        addBlock(s, BlockType.RUN_DISTANCE, TrainingZone.GA_2, 5.0);  // counts to load, not paddle
        addBlock(s, BlockType.PADDLE_DISTANCE, TrainingZone.RECOVERY, 3.0); // excluded entirely
        mark(s, a, AttendanceStatus.PRESENT);

        mvc.perform(get("/api/athletes/{id}/load", a.getId()).param("year", String.valueOf(year)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.ageCategory", is("U14")))
                .andExpect(jsonPath("$.seasonalKm", is(13.0)))        // 8 + 5, recovery excluded
                .andExpect(jsonPath("$.seasonalPaddleKm", is(8.0)))   // paddle only
                .andExpect(jsonPath("$.weeklyKm", is(13.0)))          // today is within the week
                .andExpect(jsonPath("$.ltadTargetMinKm", is(700.0)))
                .andExpect(jsonPath("$.ltadTargetMaxKm", is(1530.0)))
                .andExpect(jsonPath("$.zoneBreakdown", hasSize(2)));  // GA_1, GA_2 (recovery omitted)
    }

    @Test
    void excludesOpenAndAbsentSessions() throws Exception {
        Athlete a = athlete(year - 14);
        CoachSession open = session(SessionStatus.OPEN);      // present but not completed
        addBlock(open, BlockType.PADDLE_DISTANCE, TrainingZone.GA_1, 8.0);
        mark(open, a, AttendanceStatus.PRESENT);
        CoachSession done = session(SessionStatus.COMPLETED); // completed but absent
        addBlock(done, BlockType.PADDLE_DISTANCE, TrainingZone.GA_1, 9.0);
        mark(done, a, AttendanceStatus.ABSENT);

        mvc.perform(get("/api/athletes/{id}/load", a.getId()).param("year", String.valueOf(year)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.seasonalKm", is(0.0)))
                .andExpect(jsonPath("$.seasonalPaddleKm", is(0.0)))
                .andExpect(jsonPath("$.zoneBreakdown", hasSize(0)));
    }

    @Test
    void unknownAthleteReturns404() throws Exception {
        mvc.perform(get("/api/athletes/{id}/load", UUID.randomUUID()))
                .andExpect(status().isNotFound());
    }
}
