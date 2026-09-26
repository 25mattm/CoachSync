package com.coachsync.web;

import com.coachsync.domain.CoachSession;
import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.Team;
import com.coachsync.domain.enums.BlockType;
import com.coachsync.domain.enums.SessionStatus;
import com.coachsync.domain.enums.TrainingZone;
import com.coachsync.repository.CoachSessionRepository;
import com.coachsync.repository.SessionBlockRepository;
import com.coachsync.repository.TeamRepository;
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
class TeamAnalyticsControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private TeamRepository teams;
    @Autowired private CoachSessionRepository sessions;
    @Autowired private SessionBlockRepository blocks;

    private final int year = LocalDate.now().getYear();

    private Team team(String name) {
        Team t = new Team();
        t.setTeamName(name);
        return teams.save(t);
    }

    private CoachSession session(Team team, SessionStatus statusValue) {
        CoachSession s = new CoachSession();
        s.setSessionName("Practice");
        s.setScheduledDate(LocalDate.now());
        s.setStatus(statusValue);
        s.setTeam(team);
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

    @Test
    void seasonalAndWeeklyTeamLoadWithAllSixZones() throws Exception {
        Team t = team("Seniors");
        CoachSession s = session(t, SessionStatus.COMPLETED);
        addBlock(s, BlockType.PADDLE_DISTANCE, TrainingZone.GA_1, 10.0);
        addBlock(s, BlockType.RUN_DISTANCE, TrainingZone.E_1, 4.0);
        addBlock(s, BlockType.PADDLE_DISTANCE, TrainingZone.RECOVERY, 2.0); // excluded

        mvc.perform(get("/api/teams/{id}/load", t.getId()).param("year", String.valueOf(year)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.seasonalKm", is(14.0)))   // 10 + 4, recovery excluded
                .andExpect(jsonPath("$.weeklyKm", is(14.0)))
                .andExpect(jsonPath("$.zoneBreakdown", hasSize(6)))      // all six, fixed order
                .andExpect(jsonPath("$.zoneBreakdown[0].zone", is("GA_1")))
                .andExpect(jsonPath("$.zoneBreakdown[0].km", is(10.0)))
                .andExpect(jsonPath("$.zoneBreakdown[1].km", is(0.0)))   // GA_2 — no blocks
                .andExpect(jsonPath("$.zoneBreakdown[2].zone", is("E_1")))
                .andExpect(jsonPath("$.zoneBreakdown[2].km", is(4.0)));
    }

    @Test
    void excludesOtherTeamsAndOpenSessions() throws Exception {
        Team t = team("A");
        Team other = team("B");
        CoachSession open = session(t, SessionStatus.OPEN);          // t's, but not completed
        addBlock(open, BlockType.PADDLE_DISTANCE, TrainingZone.GA_1, 9.0);
        CoachSession otherTeam = session(other, SessionStatus.COMPLETED); // completed, but not t's
        addBlock(otherTeam, BlockType.PADDLE_DISTANCE, TrainingZone.GA_1, 7.0);

        mvc.perform(get("/api/teams/{id}/load", t.getId()).param("year", String.valueOf(year)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.seasonalKm", is(0.0)))
                .andExpect(jsonPath("$.zoneBreakdown[0].km", is(0.0)));
    }

    @Test
    void unknownTeamReturns404() throws Exception {
        mvc.perform(get("/api/teams/{id}/load", UUID.randomUUID()))
                .andExpect(status().isNotFound());
    }
}
