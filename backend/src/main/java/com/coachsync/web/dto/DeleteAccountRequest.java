package com.coachsync.web.dto;

import jakarta.validation.constraints.NotBlank;

/**
 * {@code authorizationCode} comes from a fresh Sign in with Apple authorization, which also confirms
 * the person at the device means it. {@code clientId} is the app's bundle ID the code was issued for
 * (iOS and macOS differ).
 */
public record DeleteAccountRequest(
        @NotBlank String authorizationCode,
        @NotBlank String clientId) {
}
