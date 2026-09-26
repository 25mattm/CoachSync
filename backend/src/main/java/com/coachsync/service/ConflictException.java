package com.coachsync.service;

/**
 * Thrown when a request violates a business rule that conflicts with current
 * state — e.g. deleting an athlete with recorded history, deleting a completed
 * session, or an edit that would strand recorded results. Maps to HTTP 409.
 */
public class ConflictException extends RuntimeException {

    public ConflictException(String message) {
        super(message);
    }
}
