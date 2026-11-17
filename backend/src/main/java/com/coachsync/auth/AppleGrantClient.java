package com.coachsync.auth;

/**
 * Apple's side of account deletion: confirming a fresh authorization, and revoking the app's Sign
 * in with Apple grant. Implementations report failures as values instead of throwing, because
 * whether a failure blocks deletion is the caller's decision.
 */
public interface AppleGrantClient {

    /** Exchanges a single-use authorization code. The code can't be used again after this. */
    Exchange exchange(String authorizationCode, String clientId);

    /** Revokes a token from {@link Exchange.Confirmed}. False means try again later. */
    boolean revoke(String token, String tokenTypeHint, String clientId);

    sealed interface Exchange {
        /** Apple accepted the code, which belongs to {@code appleUserId}. */
        record Confirmed(String appleUserId, String token, String tokenTypeHint) implements Exchange {}

        /** Apple refused the code itself: it's invalid, expired or already used. */
        record Rejected() implements Exchange {}

        /** Apple couldn't answer, or this server isn't set up to ask. Says nothing about the code. */
        record Unavailable() implements Exchange {}
    }
}
