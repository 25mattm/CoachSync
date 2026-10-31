package com.coachsync.service;

import com.coachsync.auth.AppleGrantClient;
import com.coachsync.domain.PendingAppleRevocation;
import com.coachsync.repository.PendingAppleRevocationRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

/**
 * Revokes Sign in with Apple grants, and keeps retrying any that fail: the deletion they belong to
 * has already committed, so nothing else would ever try again.
 */
@Service
public class AppleRevocationQueue {

    private static final Logger log = LoggerFactory.getLogger(AppleRevocationQueue.class);

    /** Hourly for two days, then stop holding the token. */
    static final int MAX_ATTEMPTS = 48;

    private final AppleGrantClient apple;
    private final PendingAppleRevocationRepository pending;

    public AppleRevocationQueue(AppleGrantClient apple, PendingAppleRevocationRepository pending) {
        this.apple = apple;
        this.pending = pending;
    }

    /** Never throws: the account is already deleted, and that's what the coach must be told. */
    public void revokeOrQueue(String token, String tokenTypeHint, String clientId) {
        if (attempt(token, tokenTypeHint, clientId)) {
            return;
        }
        try {
            PendingAppleRevocation queued = pending.save(new PendingAppleRevocation(token, tokenTypeHint, clientId));
            log.warn("Apple grant revocation queued for retry: {}", queued.getId());
        } catch (RuntimeException ex) {
            log.error("Apple grant not revoked and couldn't be queued: {}", ex.getClass().getSimpleName());
        }
    }

    @Scheduled(initialDelayString = "PT1H", fixedDelayString = "PT1H")
    public void retryPending() {
        for (PendingAppleRevocation item : pending.findAll()) {
            if (attempt(item.getToken(), item.getTokenTypeHint(), item.getClientId())) {
                pending.delete(item);
                continue;
            }
            item.recordFailedAttempt();
            if (item.getAttempts() >= MAX_ATTEMPTS) {
                log.error("Gave up revoking Apple grant after {} attempts: {}", MAX_ATTEMPTS, item.getId());
                pending.delete(item);
            } else {
                pending.save(item);
            }
        }
    }

    private boolean attempt(String token, String tokenTypeHint, String clientId) {
        try {
            return apple.revoke(token, tokenTypeHint, clientId);
        } catch (RuntimeException ex) {
            log.warn("Apple grant not revoked: {}", ex.getClass().getSimpleName());
            return false;
        }
    }
}
