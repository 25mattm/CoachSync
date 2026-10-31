package com.coachsync.service;

import com.coachsync.auth.AppleGrantClient;
import com.coachsync.domain.PendingAppleRevocation;
import com.coachsync.repository.PendingAppleRevocationRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@SpringBootTest
class AppleRevocationQueueTest {

    @Autowired private AppleRevocationQueue queue;
    @Autowired private PendingAppleRevocationRepository pending;
    @MockitoBean private AppleGrantClient apple;

    @BeforeEach
    void startEmpty() {
        pending.deleteAll();
    }

    @Test
    void aSuccessfulRetryRemovesTheToken() {
        pending.save(new PendingAppleRevocation("t", "refresh_token", "client"));
        when(apple.revoke("t", "refresh_token", "client")).thenReturn(true);

        queue.retryPending();

        assertThat(pending.count()).isZero();
    }

    @Test
    void aFailedRetryKeepsTheTokenAndCountsTheAttempt() {
        pending.save(new PendingAppleRevocation("t", "refresh_token", "client"));
        when(apple.revoke(any(), any(), any())).thenReturn(false);

        queue.retryPending();

        assertThat(pending.findAll()).singleElement()
                .satisfies(item -> assertThat(item.getAttempts()).isEqualTo(1));
    }

    @Test
    void itStopsHoldingTheTokenWhenRetriesRunOut() {
        PendingAppleRevocation item = new PendingAppleRevocation("t", "refresh_token", "client");
        for (int i = 0; i < AppleRevocationQueue.MAX_ATTEMPTS - 1; i++) {
            item.recordFailedAttempt();
        }
        pending.save(item);
        when(apple.revoke(any(), any(), any())).thenThrow(new IllegalStateException("still down"));

        queue.retryPending();

        assertThat(pending.count()).isZero();
    }
}
