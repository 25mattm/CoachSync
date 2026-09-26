package com.coachsync.service;

/**
 * Thrown when a verified identity is not authorized for this club — e.g. an Apple ID that signed in
 * successfully but is not on the approved-coach allowlist. Maps to HTTP 403 (distinct from 401, which
 * means the credential itself could not be verified).
 */
public class ForbiddenException extends RuntimeException {

    public ForbiddenException(String message) {
        super(message);
    }
}
