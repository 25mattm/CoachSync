package com.coachsync.web;

import com.coachsync.domain.Club;
import com.coachsync.domain.Coach;
import com.coachsync.repository.ClubRepository;
import com.coachsync.repository.CoachRepository;
import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import java.util.UUID;

import static org.hamcrest.Matchers.is;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.containsString;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * {@code POST /api/coaches/{id}/remove}, through the real filter chain. Uses {@code jwt()} rather than
 * {@code @WithMockUser} so {@code ActiveCoachFilter} and {@code ClubMembershipWriteGuard} both run.
 *
 * <p>Not {@code @Transactional} — same reasoning as {@link CrossClubIsolationTest}.
 */
@SpringBootTest
@AutoConfigureMockMvc
class CoachRemovalTest {

    /** On coachsync.auth.allowed-emails in test properties. */
    private static final String OPERATOR_EMAIL = "pat@example.com";

    @Autowired private MockMvc mvc;
    @Autowired private CoachRepository coaches;
    @Autowired private ClubRepository clubs;

    private Club club;
    private UUID coachId;
    private UUID operatorId;

    @BeforeEach
    void seed() {
        club = new Club();
        club.setName("Club-" + UUID.randomUUID());
        club = clubs.save(club);
        coachId = saveCoach("leaving@example.com", club);
        operatorId = saveCoach(OPERATOR_EMAIL, null);   // the operator belongs to no club
    }

    private UUID saveCoach(String email, Club in) {
        Coach coach = new Coach();
        coach.setName("Coach-" + UUID.randomUUID());
        coach.setEmail(email);
        coach.setAppleUserId("apple-" + UUID.randomUUID());
        coach.setClub(in);
        return coaches.save(coach).getId();
    }

    private RequestPostProcessor clubToken(UUID id) {
        return jwt().jwt(j -> j.subject(id.toString()).claim("club", club.getId().toString()));
    }

    /** What a coach with no club is issued. */
    private RequestPostProcessor clubLessToken(UUID id) {
        return jwt().jwt(j -> j.subject(id.toString()));
    }

    private Club clubOf(UUID id) {
        return coaches.findById(id).orElseThrow().getClub();
    }

    @Test
    void removalRejectsTheCoachsExistingTokenOnTheirNextRequest() throws Exception {
        mvc.perform(get("/api/athletes").with(clubToken(coachId))).andExpect(status().isOk());

        mvc.perform(post("/api/coaches/{id}/remove", coachId).with(clubLessToken(operatorId)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id", is(coachId.toString())));

        assertNull(clubOf(coachId));
        mvc.perform(get("/api/athletes").with(clubToken(coachId))).andExpect(status().isUnauthorized());
    }

    @Test
    void aRemovedCoachSigningInAgainSeesNothingOfTheClub() throws Exception {
        String athleteId = JsonPath.read(mvc.perform(post("/api/athletes").with(clubToken(coachId))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"firstName\":\"Ada\",\"lastName\":\"Lovelace\",\"dateOfBirth\":\"2014-05-01\"}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(), "$.id");

        mvc.perform(post("/api/coaches/{id}/remove", coachId).with(clubLessToken(operatorId)))
                .andExpect(status().isOk());

        mvc.perform(get("/api/athletes").with(clubLessToken(coachId)))
                .andExpect(status().isOk())
                .andExpect(content().string(not(containsString(athleteId))));
        mvc.perform(get("/api/athletes/{id}", athleteId).with(clubLessToken(coachId)))
                .andExpect(status().isNotFound());
    }

    @Test
    void aRemovedCoachNeedsAFreshApprovalToComeBack() throws Exception {
        mvc.perform(post("/api/coaches/{id}/remove", coachId).with(clubLessToken(operatorId)))
                .andExpect(status().isOk());

        // Nothing to approve until they ask again.
        mvc.perform(post("/api/coaches/{id}/approve", coachId).with(clubLessToken(operatorId)))
                .andExpect(status().isConflict());

        mvc.perform(post("/api/clubs/join").with(clubLessToken(coachId))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"joinCode\":\"%s\"}".formatted(club.getJoinCode())))
                .andExpect(status().isOk());
        assertNull(clubOf(coachId), "a join request alone must not restore membership");

        mvc.perform(post("/api/coaches/{id}/approve", coachId).with(clubLessToken(operatorId)))
                .andExpect(status().isOk());
        assertEquals(club.getId(), clubOf(coachId).getId());
    }

    @Test
    void removalKeepsAttributionOnTheClubsHistory() throws Exception {
        String sessionId = JsonPath.read(mvc.perform(post("/api/sessions").with(clubToken(coachId))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"sessionName\":\"Practice\",\"scheduledDate\":\"2026-06-16\"}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(), "$.id");

        mvc.perform(post("/api/coaches/{id}/remove", coachId).with(clubLessToken(operatorId)))
                .andExpect(status().isOk());

        UUID clubmateId = saveCoach("stays@example.com", club);
        mvc.perform(get("/api/sessions/{id}", sessionId).with(clubToken(clubmateId)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.coachId", is(coachId.toString())));
        // ...but they are gone from the club's roster.
        mvc.perform(get("/api/coaches/{id}", coachId).with(clubToken(clubmateId)))
                .andExpect(status().isNotFound());
    }

    @Test
    void aClubmateWhoIsNotTheOperatorCannotRemoveACoach() throws Exception {
        UUID clubmateId = saveCoach("clubmate@example.com", club);

        mvc.perform(post("/api/coaches/{id}/remove", coachId).with(clubToken(clubmateId)))
                .andExpect(status().isForbidden());

        assertNotNull(clubOf(coachId));
    }

    @Test
    void aClubLessCoachWhoIsNotTheOperatorCannotRemoveACoach() throws Exception {
        // This route passes ClubMembershipWriteGuard for the operator's sake, so OperatorGuard has to
        // be what stops a stranger awaiting approval.
        UUID strangerId = saveCoach("stranger@example.com", null);

        mvc.perform(post("/api/coaches/{id}/remove", coachId).with(clubLessToken(strangerId)))
                .andExpect(status().isForbidden());

        assertNotNull(clubOf(coachId));
    }

    @Test
    void removingAnUnknownCoachReturns404() throws Exception {
        mvc.perform(post("/api/coaches/{id}/remove", UUID.randomUUID()).with(clubLessToken(operatorId)))
                .andExpect(status().isNotFound());
    }

    @Test
    void removingACoachWithNoClubReturns409() throws Exception {
        UUID pendingId = saveCoach("pending@example.com", null);

        mvc.perform(post("/api/coaches/{id}/remove", pendingId).with(clubLessToken(operatorId)))
                .andExpect(status().isConflict());
    }
}
