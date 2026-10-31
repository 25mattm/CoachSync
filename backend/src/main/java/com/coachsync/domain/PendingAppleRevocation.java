package com.coachsync.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;

import java.time.Instant;

/**
 * A Sign in with Apple grant still to be revoked after its account was deleted, because Apple
 * couldn't be reached at the time. Holds no coach reference: the account is already gone. Removed
 * once the revoke succeeds or retries run out. Not tenant-scoped, as the retry job has no club.
 */
@Entity
@Table(name = "pending_apple_revocation")
public class PendingAppleRevocation extends BaseEntity {

    @Column(nullable = false, length = 2048)
    private String token;

    @Column(nullable = false)
    private String tokenTypeHint;

    @Column(nullable = false)
    private String clientId;

    @Column(nullable = false)
    private int attempts;

    private Instant createdAt = Timestamps.now();

    protected PendingAppleRevocation() {
    }

    public PendingAppleRevocation(String token, String tokenTypeHint, String clientId) {
        this.token = token;
        this.tokenTypeHint = tokenTypeHint;
        this.clientId = clientId;
    }

    public String getToken() {
        return token;
    }

    public String getTokenTypeHint() {
        return tokenTypeHint;
    }

    public String getClientId() {
        return clientId;
    }

    public int getAttempts() {
        return attempts;
    }

    public void recordFailedAttempt() {
        attempts++;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
