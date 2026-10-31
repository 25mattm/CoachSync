package com.coachsync.web;

import com.coachsync.auth.AppleTokenRevoker;
import com.coachsync.domain.Coach;
import com.coachsync.repository.CoachRepository;
import com.coachsync.web.ClubFixtures.ClubFixture;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * In-app account deletion (App Store Review Guideline 5.1.1(v)). Not {@code @Transactional}, for the
 * same reason as {@link CrossClubIsolationTest}.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import(ClubFixtures.class)
class AccountDeletionTest {

    private static final String CLIENT_ID = "com.example.CoachSync";

    @Autowired private MockMvc mvc;
    @Autowired private ClubFixtures fixtures;
    @Autowired private CoachRepository coaches;
    @MockitoBean private AppleTokenRevoker revoker;

    private ResultActions deleteAccount(RequestPostProcessor token, String clientId) throws Exception {
        return mvc.perform(post("/api/account/delete").with(token).contentType(MediaType.APPLICATION_JSON)
                .content("{\"authorizationCode\":\"code\",\"clientId\":\"" + clientId + "\"}"));
    }

    private void authorASession(RequestPostProcessor token) throws Exception {
        mvc.perform(post("/api/sessions").with(token).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"sessionName\":\"Practice\",\"scheduledDate\":\"2026-06-16\"}"))
                .andExpect(status().isCreated());
    }

    @Test
    void aCoachWithNoHistoryIsRemovedAndTheirAppleGrantRevoked() throws Exception {
        ClubFixture f = fixtures.club();

        deleteAccount(fixtures.token(f), CLIENT_ID).andExpect(status().isNoContent());

        assertThat(coaches.findById(f.coachId())).isEmpty();
        verify(revoker).revoke("code", CLIENT_ID);
    }

    @Test
    void aCoachWithHistoryIsAnonymizedAndTheClubKeepsItsHistory() throws Exception {
        ClubFixture f = fixtures.club("Alice");
        RequestPostProcessor token = fixtures.token(f);
        authorASession(token);

        deleteAccount(token, CLIENT_ID).andExpect(status().isNoContent());

        Coach kept = coaches.findById(f.coachId()).orElseThrow();
        assertThat(kept.getName()).isEqualTo("Former coach");
        assertThat(kept.getEmail()).isNull();
        assertThat(kept.getAppleUserId()).isNull();
        assertThat(kept.getRole()).isNull();
        assertThat(kept.getRequestedClub()).isNull();

        // The deleted coach's token is dead immediately, even with 30 days left on it.
        mvc.perform(get("/api/sessions").with(token)).andExpect(status().isUnauthorized());
    }

    @Test
    void aClubmatesHistoryAndAccountAreUntouched() throws Exception {
        ClubFixture f = fixtures.club("Alice");
        ClubFixture other = fixtures.club("Bob");

        deleteAccount(fixtures.token(f), CLIENT_ID).andExpect(status().isNoContent());

        assertThat(coaches.findById(other.coachId()).orElseThrow().getName()).isEqualTo("Bob");
        mvc.perform(get("/api/sessions").with(fixtures.token(other))).andExpect(status().isOk());
    }

    @Test
    void aCoachStillAwaitingApprovalCanDeleteTheirAccount() throws Exception {
        UUID pending = fixtures.pendingCoach();

        deleteAccount(fixtures.pendingToken(pending), CLIENT_ID).andExpect(status().isNoContent());

        assertThat(coaches.findById(pending)).isEmpty();
    }

    @Test
    void aFailureAtAppleNeverBlocksDeletionOfTheAccount() throws Exception {
        ClubFixture f = fixtures.club();
        doThrow(new IllegalStateException("apple is down")).when(revoker).revoke(any(), any());

        // The real revoker swallows its own failures; this proves the data is gone before it runs.
        try {
            deleteAccount(fixtures.token(f), CLIENT_ID);
        } catch (Exception ignored) {
            // MockMvc rethrows the stubbed failure, which the real revoker would have logged.
        }

        assertThat(coaches.findById(f.coachId())).isEmpty();
    }

    @Test
    void anUnknownClientIdIsRefusedBeforeAnythingIsDeleted() throws Exception {
        ClubFixture f = fixtures.club();

        deleteAccount(fixtures.token(f), "com.attacker.App").andExpect(status().isBadRequest());

        assertThat(coaches.findById(f.coachId())).isPresent();
        verify(revoker, never()).revoke(any(), any());
    }

    @Test
    void anAnonymousCallerIsRejected() throws Exception {
        mvc.perform(post("/api/account/delete").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"authorizationCode\":\"code\",\"clientId\":\"" + CLIENT_ID + "\"}"))
                .andExpect(status().isUnauthorized());
    }
}
