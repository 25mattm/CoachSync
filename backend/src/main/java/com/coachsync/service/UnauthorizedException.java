package com.coachsync.service;

/** Thrown when a credential cannot be verified (e.g. a bad Apple token). Maps to HTTP 401. */
public class UnauthorizedException extends RuntimeException {

    public UnauthorizedException(String message) {
        super(message);
    }

    public UnauthorizedException(String message, Throwable cause) {
        super(message, cause);
    }
}
