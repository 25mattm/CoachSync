package com.coachsync.web;

import com.coachsync.domain.Club;
import com.coachsync.domain.Coach;
import com.coachsync.repository.ClubRepository;
import com.coachsync.repository.CoachRepository;
import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The end-to-end approval queue from the multi-club tenancy plan's settled slice 4 design: an
 * operator creates a club and gets a join code; a coach submits it and stays club-less; the operator
 * approves the coach; and only a <em>freshly issued</em> token (a re-sign-in, mirrored here by
 * re-reading the coach's persisted club rather than minting a new JWT) actually carries the club.
 *
 * <p>Not {@code @Transactional} — same reasoning as {@link CrossClubIsolationTest}: a class
 * transaction would fix Hibernate's tenant before each request's JWT is applied.
 */
@SpringBootTest
@AutoConfigureMockMvc
class JoinFlowTest {

    @Autowired private MockMvc mvc;
    @Autowired private CoachRepository coaches;
    @Autowired private ClubRepository clubs;

    /** operator's email is on coachsync.auth.allowed-emails in test properties. */
    private static final String OPERATOR_EMAIL = "pat@example.com";

    private UUID saveCoach(String email) {
        Coach coach = new Coach();
        coach.setName("Coach-" + UUID.randomUUID());
        coach.setEmail(email);
        coach.setAppleUserId("apple-" + UUID.randomUUID());
        return coaches.save(coach).getId();
    }

    private RequestPostProcessor asCoach(UUID coachId) {
        return jwt().jwt(j -> j.subject(coachId.toString()));
    }

    @Test
    void fullLifecycleFromClubCreationToApprovedAccess() throws Exception {
        UUID operatorId = saveCoach(OPERATOR_EMAIL);
        UUID applicantId = saveCoach("newcoach@example.com");

        // 1. Operator creates a club and gets back its join code.
        String createBody = mvc.perform(post("/api/clubs").with(asCoach(operatorId))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"Test Club\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.joinCode").exists())
                .andReturn().getResponse().getContentAsString();
        String joinCode = JsonPath.read(createBody, "$.joinCode");
        String createdClubId = JsonPath.read(createBody, "$.id");

        // 2. The applicant submits the join code. This only registers intent — no club claim would
        //    ever be issued for them yet.
        mvc.perform(post("/api/clubs/join").with(asCoach(applicantId))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"joinCode\":\"%s\"}".formatted(joinCode)))
                .andExpect(status().isOk());
        assertNull(coaches.findById(applicantId).orElseThrow().getClub(),
                "submitting a join code alone must not grant club membership");
        // .getId() on a lazy Club proxy never needs an open session — Hibernate knows a proxy's own
        // id without initializing it; .getJoinCode() would throw LazyInitializationException here.
        assertEquals(UUID.fromString(createdClubId),
                coaches.findById(applicantId).orElseThrow().getRequestedClub().getId());

        // Still nothing club-A-specific to see: no operator has approved them, so a same-shaped token
        // with no club claim (what they'd actually be issued right now) resolves to NO_TENANT — a
        // fixed sentinel shared by every other pending coach in the whole test run, so this asserts
        // the response is stable across step 5 below rather than assuming it's exactly empty.
        String preApprovalView = mvc.perform(get("/api/athletes").with(asCoach(applicantId)))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();

        // 3. Operator approves.
        mvc.perform(post("/api/coaches/{id}/approve", applicantId).with(asCoach(operatorId)))
                .andExpect(status().isOk());
        Coach approved = coaches.findById(applicantId).orElseThrow();
        assertNull(approved.getRequestedClub(), "approval clears the pending request");
        UUID clubId = approved.getClub().getId();

        // 4. The coach's NEXT token (a fresh sign-in) carries the club claim and unlocks their data —
        //    this is JwtService's existing "only an approved coach carries a club" behaviour, now
        //    reachable end-to-end through the join/approve flow instead of only by direct DB seeding.
        RequestPostProcessor freshToken = jwt().jwt(j -> j.subject(applicantId.toString()).claim("club", clubId.toString()));
        mvc.perform(get("/api/athletes").with(freshToken))
                .andExpect(status().isOk());

        // 5. The OLD pre-approval token (no club claim, never reissued) must stay inert — this is the
        //    invariant this class's own javadoc claims ("only a freshly issued token... actually
        //    carries the club"), pinned here rather than left as a documentation-only promise. The
        //    approval must not have changed what this stale token can see, whatever that was.
        mvc.perform(get("/api/athletes").with(asCoach(applicantId)))
                .andExpect(status().isOk())
                .andExpect(content().string(preApprovalView));
    }

    @Test
    void nonOperatorCannotCreateAClub() throws Exception {
        UUID notOperator = saveCoach("notops@example.com");

        mvc.perform(post("/api/clubs").with(asCoach(notOperator))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"Test Club\"}"))
                .andExpect(status().isForbidden());
    }

    @Test
    void nonOperatorCannotApproveOrListPending() throws Exception {
        UUID notOperator = saveCoach("notops@example.com");
        UUID applicant = saveCoach("applicant@example.com");

        mvc.perform(post("/api/coaches/{id}/approve", applicant).with(asCoach(notOperator)))
                .andExpect(status().isForbidden());
        mvc.perform(get("/api/coaches/pending").with(asCoach(notOperator)))
                .andExpect(status().isForbidden());
    }

    @Test
    void joiningWithAnUnknownCodeIs404() throws Exception {
        UUID applicant = saveCoach("applicant@example.com");

        mvc.perform(post("/api/clubs/join").with(asCoach(applicant))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"joinCode\":\"NOPE0000\"}"))
                .andExpect(status().isNotFound());
    }

    @Test
    void aCoachAlreadyInAClubCannotJoinAnother() throws Exception {
        Club club = new Club();
        club.setName("Test Club");
        Club saved = clubs.save(club);
        Coach coach = new Coach();
        coach.setName("Already In");
        coach.setEmail("already@example.com");
        coach.setAppleUserId("apple-" + UUID.randomUUID());
        coach.setClub(saved);
        UUID coachId = coaches.save(coach).getId();

        Club other = new Club();
        other.setName("Other Club");
        clubs.save(other);

        mvc.perform(post("/api/clubs/join").with(asCoach(coachId))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"joinCode\":\"%s\"}".formatted(other.getJoinCode())))
                .andExpect(status().isConflict());
    }

    @Test
    void approvingACoachWithNoPendingRequestIsConflict() throws Exception {
        UUID operatorId = saveCoach(OPERATOR_EMAIL);
        UUID noRequest = saveCoach("norequest@example.com");

        mvc.perform(post("/api/coaches/{id}/approve", noRequest).with(asCoach(operatorId)))
                .andExpect(status().isConflict());
    }

    @Test
    void approvingAnUnknownCoachIs404() throws Exception {
        UUID operatorId = saveCoach(OPERATOR_EMAIL);

        mvc.perform(post("/api/coaches/{id}/approve", UUID.randomUUID()).with(asCoach(operatorId)))
                .andExpect(status().isNotFound());
    }

    /**
     * Without this guard, submitting a second join code would silently swap {@code requestedClub}
     * out from under an operator who already reviewed the first request (via {@code
     * GET /api/coaches/pending}) — their {@code approve} call would then land against a club they
     * never actually vetted the coach for.
     */
    @Test
    void rejoiningWithADifferentCodeBeforeApprovalIsConflict() throws Exception {
        UUID applicantId = saveCoach("applicant@example.com");
        Club clubA = clubs.save(newClub("Club A"));
        Club clubB = clubs.save(newClub("Club B"));

        mvc.perform(post("/api/clubs/join").with(asCoach(applicantId))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"joinCode\":\"%s\"}".formatted(clubA.getJoinCode())))
                .andExpect(status().isOk());

        mvc.perform(post("/api/clubs/join").with(asCoach(applicantId))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"joinCode\":\"%s\"}".formatted(clubB.getJoinCode())))
                .andExpect(status().isConflict());

        // The original request survived untouched.
        assertEquals(clubA.getId(), coaches.findById(applicantId).orElseThrow().getRequestedClub().getId());
    }

    @Test
    void deAllowlistedOperatorLosesOperatorAccessOnNextCall() throws Exception {
        UUID operatorId = saveCoach(OPERATOR_EMAIL);
        RequestPostProcessor operatorToken = asCoach(operatorId);

        mvc.perform(post("/api/clubs").with(operatorToken)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"Test Club\"}"))
                .andExpect(status().isCreated());

        Coach operator = coaches.findById(operatorId).orElseThrow();
        operator.setEmail("removed-from-allowlist@example.com");
        coaches.save(operator);

        // Same token, same OperatorGuard call — OperatorGuard re-fetches and re-checks on every
        // call rather than trusting anything cached from the first success.
        mvc.perform(post("/api/clubs").with(operatorToken)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"Second Club\"}"))
                .andExpect(status().isForbidden());
    }

    @Test
    void doubleApprovingAnAlreadyApprovedCoachIsConflict() throws Exception {
        UUID operatorId = saveCoach(OPERATOR_EMAIL);
        UUID applicantId = saveCoach("applicant@example.com");
        Club club = clubs.save(newClub("Test Club"));

        mvc.perform(post("/api/clubs/join").with(asCoach(applicantId))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"joinCode\":\"%s\"}".formatted(club.getJoinCode())))
                .andExpect(status().isOk());
        mvc.perform(post("/api/coaches/{id}/approve", applicantId).with(asCoach(operatorId)))
                .andExpect(status().isOk());

        // Same coach, approved a second time: requestedClub is now null, same as "never requested."
        mvc.perform(post("/api/coaches/{id}/approve", applicantId).with(asCoach(operatorId)))
                .andExpect(status().isConflict());
    }

    private static Club newClub(String name) {
        Club club = new Club();
        club.setName(name);
        return club;
    }

    @Test
    void operatorSeesPendingCoachesAcrossClubs() throws Exception {
        UUID operatorId = saveCoach(OPERATOR_EMAIL);
        Club club = new Club();
        club.setName("Test Club");
        Club saved = clubs.save(club);
        UUID applicantId = saveCoach("applicant@example.com");

        mvc.perform(post("/api/clubs/join").with(asCoach(applicantId))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"joinCode\":\"%s\"}".formatted(saved.getJoinCode())))
                .andExpect(status().isOk());

        mvc.perform(get("/api/coaches/pending").with(asCoach(operatorId)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[?(@.id == '%s')]".formatted(applicantId)).exists());
    }
}
