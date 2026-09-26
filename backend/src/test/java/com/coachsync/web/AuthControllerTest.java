package com.coachsync.web;

import com.coachsync.auth.AppleIdentity;
import com.coachsync.auth.AppleTokenVerifier;
import com.coachsync.domain.Club;
import com.coachsync.repository.ClubRepository;
import com.coachsync.repository.CoachRepository;
import com.coachsync.service.UnauthorizedException;
import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

import static org.hamcrest.Matchers.is;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Sign in with Apple + the locked API. Apple verification is stubbed (no network); the
 * backend's own HS256 token round-trip is exercised for real against a protected endpoint.
 * Deliberately NOT {@code @WithMockUser} — these tests assert the real auth boundary.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class AuthControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private CoachRepository coaches;
    @Autowired private ClubRepository clubs;
    @MockitoBean private AppleTokenVerifier verifier;

    private static final String BODY = "{\"identityToken\":\"apple-token\",\"displayName\":\"Pat\"}";

    @Test
    void firstSignInProvisionsCoach() throws Exception {
        given(verifier.verify(anyString())).willReturn(new AppleIdentity("apple-sub-1", "pat@example.com"));

        mvc.perform(post("/api/auth/apple").contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.token", notNullValue()))
                .andExpect(jsonPath("$.coach.id", notNullValue()))
                .andExpect(jsonPath("$.coach.name", is("Pat")));

        assertTrue(coaches.findByAppleUserId("apple-sub-1").isPresent(),
                "first sign-in should provision a coach linked to the Apple sub");
    }

    @Test
    void secondSignInLinksSameCoachWithoutDuplicate() throws Exception {
        given(verifier.verify(anyString())).willReturn(new AppleIdentity("apple-sub-1", "pat@example.com"));

        String first = mvc.perform(post("/api/auth/apple").contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        String second = mvc.perform(post("/api/auth/apple").contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();

        String firstCoachId = JsonPath.read(first, "$.coach.id");
        String secondCoachId = JsonPath.read(second, "$.coach.id");
        assertEquals(firstCoachId, secondCoachId, "same Apple sub should resolve to the same coach");
        assertEquals(1, coaches.count(), "no duplicate coach for a repeat sign-in");
    }

    @Test
    void unlistedEmailStillSignsInAndLandsPending() throws Exception {
        // coachsync.auth.allowed-emails is now the platform-operator gate only (see OperatorGuard),
        // not the sign-in gate: any verified Apple identity signs in and is provisioned, whether or
        // not its email is on that list.
        given(verifier.verify(anyString()))
                .willReturn(new AppleIdentity("apple-sub-stranger", "stranger@example.com"));

        mvc.perform(post("/api/auth/apple").contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isOk());

        var provisioned = coaches.findByAppleUserId("apple-sub-stranger");
        assertTrue(provisioned.isPresent(),
                "an unlisted Apple ID still signs in and is provisioned, landing club-less/pending");
        assertNull(provisioned.get().getClub(),
                "a freshly provisioned coach has no club until an operator approves them");
    }

    @Test
    void authResponseCarriesClubIdOnceApprovedButNotBefore() throws Exception {
        given(verifier.verify(anyString())).willReturn(new AppleIdentity("apple-sub-1", "pat@example.com"));

        mvc.perform(post("/api/auth/apple").contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.clubId", nullValue()));

        var coach = coaches.findByAppleUserId("apple-sub-1").orElseThrow();
        Club club = new Club();
        club.setName("Test Club");
        club = clubs.save(club);  // Coach.club has no cascade — the club must exist before assigning it
        coach.setClub(club);
        coaches.save(coach);

        mvc.perform(post("/api/auth/apple").contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.clubId", is(club.getId().toString())));
    }

    @Test
    void invalidAppleTokenReturns401() throws Exception {
        given(verifier.verify(anyString())).willThrow(new UnauthorizedException("bad token"));

        mvc.perform(post("/api/auth/apple").contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void blankIdentityTokenReturns400() throws Exception {
        mvc.perform(post("/api/auth/apple").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"identityToken\":\"\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void issuedTokenAuthorizesProtectedEndpoint() throws Exception {
        given(verifier.verify(anyString())).willReturn(new AppleIdentity("apple-sub-1", "pat@example.com"));
        String body = mvc.perform(post("/api/auth/apple").contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        String token = JsonPath.read(body, "$.token");

        mvc.perform(get("/api/athletes").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk());
    }

    @Test
    void protectedEndpointWithoutTokenReturns401() throws Exception {
        mvc.perform(get("/api/athletes"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void deletedCoachTokenIsRejectedOnTheNextRequest() throws Exception {
        // Sign in to mint a real token, then delete the coach: the still-valid (30-day) token must
        // stop working immediately — ActiveCoachFilter re-checks the coach exists on every request.
        given(verifier.verify(anyString())).willReturn(new AppleIdentity("apple-sub-1", "pat@example.com"));
        String body = mvc.perform(post("/api/auth/apple").contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        String token = JsonPath.read(body, "$.token");
        String coachId = JsonPath.read(body, "$.coach.id");

        mvc.perform(get("/api/athletes").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk());

        coaches.deleteById(UUID.fromString(coachId));

        mvc.perform(get("/api/athletes").header("Authorization", "Bearer " + token))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void deallowlistingACoachNoLongerRevokesOrdinaryAccess() throws Exception {
        // coachsync.auth.allowed-emails stopped being the data boundary in slice 4 — it only gates
        // the operator-only endpoints (OperatorGuard) now. Falling off it no longer revokes a
        // regular coach's already-issued token; only a club change does (see RevocationTest).
        given(verifier.verify(anyString())).willReturn(new AppleIdentity("apple-sub-1", "pat@example.com"));
        String body = mvc.perform(post("/api/auth/apple").contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        String token = JsonPath.read(body, "$.token");
        String coachId = JsonPath.read(body, "$.coach.id");

        var coach = coaches.findById(UUID.fromString(coachId)).orElseThrow();
        coach.setEmail("removed-from-allowlist@example.com");
        coaches.save(coach);

        mvc.perform(get("/api/athletes").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk());
    }
}
