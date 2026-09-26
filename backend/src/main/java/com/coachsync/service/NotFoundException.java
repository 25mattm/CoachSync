package com.coachsync.service;

/** Thrown when a requested resource does not exist. Maps to HTTP 404. */
public class NotFoundException extends RuntimeException {

    public NotFoundException(String message) {
        super(message);
    }
}
