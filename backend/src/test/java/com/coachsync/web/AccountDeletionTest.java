package com.coachsync.web;

import com.coachsync.auth.AppleGrantClient;
import com.coachsync.auth.AppleGrantClient.Exchange;
import com.coachsync.domain.Coach;
import com.coachsync.repository.CoachRepository;
import com.coachsync.repository.PendingAppleRevocationRepository;
import com.coachsync.web.ClubFixtures.ClubFixture;
import org.junit.jupiter.api.BeforeEach;
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

import java.time.Instant;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
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
    @Autowired private PendingAppleRevocationRepository pendingRevocations;
    @MockitoBean private AppleGrantClient apple;

    @BeforeEach
    void appleRevokesSuccessfully() {
        pendingRevocations.deleteAll();
        when(apple.revoke(any(), any(), any())).thenReturn(true);
    }

    private void appleConfirms(UUID coachId) {
        String appleUserId = coaches.findById(coachId).orElseThrow().getAppleUserId();
        when(apple.exchange("code", CLIENT_ID))
                .thenReturn(new Exchange.Confirmed(appleUserId, "refresh-1", "refresh_token"));
    }

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
        appleConfirms(f.coachId());

        deleteAccount(fixtures.token(f), CLIENT_ID).andExpect(status().isNoContent());

        assertThat(coaches.findById(f.coachId())).isEmpty();
        verify(apple).revoke("refresh-1", "refresh_token", CLIENT_ID);
        assertThat(pendingRevocations.count()).isZero();
    }

    @Test
    void aCoachWithHistoryIsAnonymizedAndTheClubKeepsItsHistory() throws Exception {
        ClubFixture f = fixtures.club("Alice");
        RequestPostProcessor token = fixtures.token(f);
        authorASession(token);
        appleConfirms(f.coachId());

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

    /** Devices only take a coach whose stamp is newer, so without this their name stays forever. */
    @Test
    void anonymizingStampsTheRowSoClubmatesDevicesPickItUp() throws Exception {
        ClubFixture f = fixtures.club("Alice");
        authorASession(fixtures.token(f));
        Instant before = coaches.findById(f.coachId()).orElseThrow().getUpdatedAt();
        Thread.sleep(2);
        appleConfirms(f.coachId());

        deleteAccount(fixtures.token(f), CLIENT_ID).andExpect(status().isNoContent());

        assertThat(coaches.findById(f.coachId()).orElseThrow().getUpdatedAt()).isAfter(before);
    }

    /** A clubmate's device still holds the old details and can push them with a later stamp. */
    @Test
    void aClubmatesDeviceCannotWriteADeletedCoachBack() throws Exception {
        ClubFixture f = fixtures.club("Alice");
        RequestPostProcessor alice = fixtures.token(f);
        authorASession(alice);
        UUID bobId = saveClubmate(f);
        RequestPostProcessor bob = fixtures.token(new ClubFixture(f.clubId(), bobId));
        appleConfirms(f.coachId());
        deleteAccount(alice, CLIENT_ID).andExpect(status().isNoContent());

        String resurrect = "{\"id\":\"" + f.coachId() + "\",\"name\":\"Alice\",\"role\":\"Head\","
                + "\"updatedAt\":\"2099-01-01T00:00:00Z\"}";
        mvc.perform(post("/api/coaches").with(bob).contentType(MediaType.APPLICATION_JSON).content(resurrect))
                .andExpect(status().isConflict());
        mvc.perform(put("/api/coaches/{id}", f.coachId()).with(bob).contentType(MediaType.APPLICATION_JSON)
                        .content(resurrect))
                .andExpect(status().isConflict());

        mvc.perform(get("/api/coaches/{id}", f.coachId()).with(bob))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Former coach"));
    }

    private UUID saveClubmate(ClubFixture f) {
        Coach bob = new Coach();
        bob.setName("Bob");
        bob.setAppleUserId("apple-" + UUID.randomUUID());
        bob.setClub(coaches.findById(f.coachId()).orElseThrow().getClub());
        return coaches.save(bob).getId();
    }

    @Test
    void aClubmatesAccountIsUntouched() throws Exception {
        ClubFixture f = fixtures.club("Alice");
        ClubFixture other = fixtures.club("Bob");
        appleConfirms(f.coachId());

        deleteAccount(fixtures.token(f), CLIENT_ID).andExpect(status().isNoContent());

        assertThat(coaches.findById(other.coachId()).orElseThrow().getName()).isEqualTo("Bob");
        mvc.perform(get("/api/sessions").with(fixtures.token(other))).andExpect(status().isOk());
    }

    @Test
    void aCoachStillAwaitingApprovalCanDeleteTheirAccount() throws Exception {
        UUID pending = fixtures.pendingCoach();
        appleConfirms(pending);

        deleteAccount(fixtures.pendingToken(pending), CLIENT_ID).andExpect(status().isNoContent());

        assertThat(coaches.findById(pending)).isEmpty();
    }

    @Test
    void aCodeAppleRefusesDeletesNothing() throws Exception {
        ClubFixture f = fixtures.club();
        when(apple.exchange("code", CLIENT_ID)).thenReturn(new Exchange.Rejected());

        deleteAccount(fixtures.token(f), CLIENT_ID).andExpect(status().isForbidden());

        assertThat(coaches.findById(f.coachId())).isPresent();
        verify(apple, never()).revoke(any(), any(), any());
    }

    @Test
    void aCodeForADifferentAppleIdDeletesNothingAndRevokesNothing() throws Exception {
        ClubFixture f = fixtures.club();
        when(apple.exchange("code", CLIENT_ID))
                .thenReturn(new Exchange.Confirmed("someone-else", "refresh-1", "refresh_token"));

        deleteAccount(fixtures.token(f), CLIENT_ID).andExpect(status().isForbidden());

        assertThat(coaches.findById(f.coachId())).isPresent();
        verify(apple, never()).revoke(any(), any(), any());
    }

    @Test
    void anAppleOutageNeverBlocksDeletion() throws Exception {
        ClubFixture f = fixtures.club();
        when(apple.exchange("code", CLIENT_ID)).thenReturn(new Exchange.Unavailable());

        deleteAccount(fixtures.token(f), CLIENT_ID).andExpect(status().isNoContent());

        assertThat(coaches.findById(f.coachId())).isEmpty();
    }

    @Test
    void aFailedRevokeIsQueuedAndTheCoachStillToldItWorked() throws Exception {
        ClubFixture f = fixtures.club();
        appleConfirms(f.coachId());
        when(apple.revoke(any(), any(), any())).thenReturn(false);

        deleteAccount(fixtures.token(f), CLIENT_ID).andExpect(status().isNoContent());

        assertThat(coaches.findById(f.coachId())).isEmpty();
        assertThat(pendingRevocations.findAll()).singleElement()
                .satisfies(queued -> assertThat(queued.getToken()).isEqualTo("refresh-1"));
    }

    @Test
    void anUnexpectedErrorRevokingCannotTurnACommittedDeletionIntoAFailure() throws Exception {
        ClubFixture f = fixtures.club();
        appleConfirms(f.coachId());
        when(apple.revoke(any(), any(), any())).thenThrow(new IllegalStateException("surprise"));

        deleteAccount(fixtures.token(f), CLIENT_ID).andExpect(status().isNoContent());

        assertThat(pendingRevocations.count()).isEqualTo(1);
    }

    @Test
    void anUnknownClientIdIsRefusedBeforeAppleIsAsked() throws Exception {
        ClubFixture f = fixtures.club();

        deleteAccount(fixtures.token(f), "com.attacker.App").andExpect(status().isBadRequest());

        assertThat(coaches.findById(f.coachId())).isPresent();
        verify(apple, never()).exchange(any(), any());
    }

    @Test
    void anAnonymousCallerIsRejected() throws Exception {
        mvc.perform(post("/api/account/delete").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"authorizationCode\":\"code\",\"clientId\":\"" + CLIENT_ID + "\"}"))
                .andExpect(status().isUnauthorized());
    }
}
