package com.coachsync.web.dto;

import jakarta.validation.constraints.NotBlank;

/**
 * Sign in with Apple payload. {@code identityToken} is Apple's identity JWT;
 * {@code displayName} is the user's name, which Apple returns to the app only on the
 * first authorization (never in the token) — sent so a newly provisioned coach is named.
 */
public record AppleSignInRequest(
        @NotBlank String identityToken,
        String displayName) {
}
