package com.coachsync.auth;

/**
 * The verified identity extracted from an Apple Sign-in identity token.
 *
 * @param sub   Apple's stable user identifier (the token {@code sub}); the coach link key.
 * @param email the user's email if present (may be an Apple private-relay address, and
 *              is only included by Apple on the first authorization) — may be {@code null}.
 */
public record AppleIdentity(String sub, String email) {
}
