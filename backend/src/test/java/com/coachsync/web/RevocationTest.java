package com.coachsync.web;

import com.coachsync.domain.Club;
import com.coachsync.domain.Coach;
import com.coachsync.repository.ClubRepository;
import com.coachsync.repository.CoachRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import java.util.UUID;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * {@code ActiveCoachFilter}'s club-mismatch revocation ({@code POST /api/coaches/{id}/approve}'s
 * companion guarantee): a token minted for one club must stop working the instant the coach's
 * <em>actual</em> club diverges from the one the token claims — moved to another club, or removed
 * from theirs entirely — without waiting for the token's 30-day life to end.
 *
 * <p>Not {@code @Transactional} — same reasoning as {@link CrossClubIsolationTest}: a class
 * transaction would fix Hibernate's tenant before each request's JWT is applied.
 */
@SpringBootTest
@AutoConfigureMockMvc
class RevocationTest {

    @Autowired private MockMvc mvc;
    @Autowired private CoachRepository coaches;
    @Autowired private ClubRepository clubs;

    private UUID saveClub() {
        Club club = new Club();
        club.setName("Club-" + UUID.randomUUID());
        return clubs.save(club).getId();
    }

    private UUID saveCoachIn(UUID clubId) {
        Coach coach = new Coach();
        coach.setName("Pat");
        coach.setEmail("pat@example.com");
        coach.setAppleUserId("apple-" + UUID.randomUUID());
        coach.setClub(clubs.getReferenceById(clubId));
        return coaches.save(coach).getId();
    }

    private RequestPostProcessor tokenFor(UUID coachId, UUID claimedClub) {
        return jwt().jwt(j -> j.subject(coachId.toString()).claim("club", claimedClub.toString()));
    }

    @Test
    void aTokenStaysValidWhileClubMembershipIsUnchanged() throws Exception {
        UUID clubId = saveClub();
        UUID coachId = saveCoachIn(clubId);

        mvc.perform(get("/api/athletes").with(tokenFor(coachId, clubId)))
                .andExpect(status().isOk());
    }

    @Test
    void movingACoachToAnotherClubRevokesTheOldTokenImmediately() throws Exception {
        UUID clubA = saveClub();
        UUID clubB = saveClub();
        UUID coachId = saveCoachIn(clubA);
        RequestPostProcessor staleClubAToken = tokenFor(coachId, clubA);

        mvc.perform(get("/api/athletes").with(staleClubAToken))
                .andExpect(status().isOk());

        Coach coach = coaches.findById(coachId).orElseThrow();
        coach.setClub(clubs.getReferenceById(clubB));
        coaches.save(coach);

        // Same 30-day token, now claiming a club the coach no longer belongs to.
        mvc.perform(get("/api/athletes").with(staleClubAToken))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void removingACoachFromTheirClubRevokesTheOldTokenImmediately() throws Exception {
        UUID clubId = saveClub();
        UUID coachId = saveCoachIn(clubId);
        RequestPostProcessor staleToken = tokenFor(coachId, clubId);

        mvc.perform(get("/api/athletes").with(staleToken))
                .andExpect(status().isOk());

        Coach coach = coaches.findById(coachId).orElseThrow();
        coach.setClub(null);
        coaches.save(coach);

        mvc.perform(get("/api/athletes").with(staleToken))
                .andExpect(status().isUnauthorized());
    }

    /**
     * A deleted coach's id is free for reuse ({@code Coach} is hard-deleted, {@code id} is a
     * client-assignable UUID). Proves that reuse cannot resurrect the deleted coach's own
     * already-issued, never-reissued token — closing the gap where the revocation check would
     * otherwise see "a row exists at this id, with a matching club" and let it back in.
     */
    @Test
    void resurrectingADeletedCoachsIdDoesNotReviveTheirOldToken() throws Exception {
        UUID clubId = saveClub();
        UUID coachAId = saveCoachIn(clubId);
        RequestPostProcessor coachAToken = tokenFor(coachAId, clubId);
        UUID coachBId = saveCoachIn(clubId);
        RequestPostProcessor coachBToken = tokenFor(coachBId, clubId);

        mvc.perform(get("/api/athletes").with(coachAToken))
                .andExpect(status().isOk());

        coaches.deleteById(coachAId);
        mvc.perform(get("/api/athletes").with(coachAToken))
                .andExpect(status().isUnauthorized());

        // Coach B — an ordinary member of the same club, no special privilege — reuses coach A's old
        // id via the ordinary create-by-id upsert path. CoachService.create() never sets
        // appleUserId/email on a newly-created row, so this row can never legitimately hold a token.
        mvc.perform(post("/api/coaches").with(coachBToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"id\":\"%s\",\"name\":\"Resurrected\"}".formatted(coachAId)))
                .andExpect(status().isCreated());

        // Coach A's original, never-reissued token must still be dead.
        mvc.perform(get("/api/athletes").with(coachAToken))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void aPendingCoachTokenStaysValidRegardlessOfLaterClubChanges() throws Exception {
        // A club-less coach's token carries no club claim at all (JwtService only stamps one for an
        // approved coach). ClubTenantResolver already resolves that to NO_TENANT, so there is nothing
        // for the revocation check to catch here — it must not reject a merely-pending coach.
        Coach coach = new Coach();
        coach.setName("Pending");
        coach.setEmail("pat@example.com");
        coach.setAppleUserId("apple-" + UUID.randomUUID());
        UUID coachId = coaches.save(coach).getId();
        RequestPostProcessor pendingToken = jwt().jwt(j -> j.subject(coachId.toString()));

        mvc.perform(get("/api/athletes").with(pendingToken))
                .andExpect(status().isOk());
    }
}
