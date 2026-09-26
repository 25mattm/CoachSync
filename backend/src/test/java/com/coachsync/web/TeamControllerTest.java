package com.coachsync.web;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.CoachSession;
import com.coachsync.domain.Team;
import com.coachsync.domain.TeamMembership;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.CoachSessionRepository;
import com.coachsync.repository.TeamMembershipRepository;
import com.coachsync.repository.TeamRepository;
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
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@WithMockUser
@Transactional
class TeamControllerTest {

    @Autowired private MockMvc mvc;
    @PersistenceContext private EntityManager em;
    @Autowired private TeamRepository teams;
    @Autowired private CoachSessionRepository sessions;
    @Autowired private TeamMembershipRepository memberships;
    @Autowired private AthleteRepository athletes;

    private String createTeam(String name) throws Exception {
        String body = mvc.perform(post("/api/teams").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"teamName\":\"" + name + "\"}"))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", containsString("/api/teams/")))
                .andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.id");
    }

    private Athlete newAthlete(String first) {
        Athlete a = new Athlete();
        a.setFirstName(first);
        a.setLastName("Test");
        a.setDateOfBirth(LocalDate.of(2014, 1, 1));
        return athletes.save(a);
    }

    @Test
    void createsAndArchivesTeam() throws Exception {
        String id = createTeam("U14 Sprint");
        mvc.perform(get("/api/teams/{id}", id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.teamName", is("U14 Sprint")))
                .andExpect(jsonPath("$.archived", is(false)));
        mvc.perform(patch("/api/teams/{id}/archive", id).param("value", "true"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.archived", is(true)));
    }

    @Test
    void blankTeamNameReturns400() throws Exception {
        mvc.perform(post("/api/teams").contentType(MediaType.APPLICATION_JSON).content("{\"teamName\":\"\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors.teamName").exists());
    }

    @Test
    void deleteTeamNullifiesAndRetainsSessions() throws Exception {
        Team team = new Team();
        team.setTeamName("Doomed");
        team = teams.save(team);

        CoachSession session = new CoachSession();
        session.setSessionName("Practice");
        session.setScheduledDate(LocalDate.of(2026, 6, 16));
        session.setTeam(team);
        session = sessions.save(session);
        UUID sessionId = session.getId();
        UUID teamId = team.getId();

        mvc.perform(delete("/api/teams/{id}", teamId)).andExpect(status().isNoContent());

        assertTrue(teams.findById(teamId).isEmpty(), "team should be deleted");
        CoachSession retained = sessions.findById(sessionId).orElseThrow();
        assertNull(retained.getTeam(), "session should be retained with team nulled");
    }

    @Test
    void deleteTeamCascadesMemberships() throws Exception {
        Team team = new Team();
        team.setTeamName("Doomed");
        team = teams.save(team);
        Athlete athlete = newAthlete("Mo");
        TeamMembership m = new TeamMembership();
        m.setTeam(team);
        m.setAthlete(athlete);
        m.setJoinedDate(LocalDate.of(2026, 1, 1));
        m = memberships.save(m);
        UUID teamId = team.getId();
        UUID athleteId = athlete.getId();
        UUID membershipId = m.getId();

        // Reload the team fresh (as a separate request would) so its lazy
        // memberships collection cascade-deletes on remove.
        em.flush();
        em.clear();

        mvc.perform(delete("/api/teams/{id}", teamId)).andExpect(status().isNoContent());

        assertTrue(memberships.findById(membershipId).isEmpty(), "membership should cascade-delete");
        assertTrue(athletes.findById(athleteId).isPresent(), "athlete should be retained");
    }

    @Test
    void membershipRosterAddDuplicateAndRemove() throws Exception {
        String teamId = createTeam("Roster");
        Athlete athlete = newAthlete("Ada");
        String addBody = "{\"athleteId\":\"" + athlete.getId() + "\"}";

        mvc.perform(post("/api/teams/{id}/members", teamId)
                        .contentType(MediaType.APPLICATION_JSON).content(addBody))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", containsString("/members/")))
                .andExpect(jsonPath("$.athleteFirstName", is("Ada")));

        String roster = mvc.perform(get("/api/teams/{id}/members", teamId).param("active", "true"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[*].athleteFirstName", hasItem("Ada")))
                .andReturn().getResponse().getContentAsString();
        String membershipId = JsonPath.read(roster, "$[0].id");

        // duplicate active membership is rejected
        mvc.perform(post("/api/teams/{id}/members", teamId)
                        .contentType(MediaType.APPLICATION_JSON).content(addBody))
                .andExpect(status().isConflict());

        mvc.perform(delete("/api/teams/{id}/members/{mid}", teamId, membershipId))
                .andExpect(status().isNoContent());
        mvc.perform(get("/api/teams/{id}/members", teamId))
                .andExpect(jsonPath("$", hasSize(0)));
    }

    @Test
    void updateMembershipSetsLeftDate() throws Exception {
        // Soft-leave sync: the app sets leftDate (an update), pushed via the membership PUT.
        String teamId = createTeam("Leavers");
        Athlete athlete = newAthlete("Bo");
        String created = mvc.perform(post("/api/teams/{id}/members", teamId)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"athleteId\":\"" + athlete.getId() + "\"}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        String membershipId = JsonPath.read(created, "$.id");

        mvc.perform(put("/api/teams/{id}/members/{mid}", teamId, membershipId)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"athleteId\":\"" + athlete.getId() + "\",\"leftDate\":\"2026-06-18\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.leftDate", is("2026-06-18")));

        mvc.perform(get("/api/teams/{id}/members", teamId).param("active", "true"))
                .andExpect(jsonPath("$", hasSize(0)));
    }

    @Test
    void addUnknownAthleteReturns404() throws Exception {
        String teamId = createTeam("Empty");
        mvc.perform(post("/api/teams/{id}/members", teamId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"athleteId\":\"" + UUID.randomUUID() + "\"}"))
                .andExpect(status().isNotFound());
    }
}
