package com.coachsync.service;

/**
 * Thrown for a semantically invalid request that bean validation can't express
 * (e.g. a COMPLETE rep result with no recorded time). Maps to HTTP 400.
 */
public class BadRequestException extends RuntimeException {

    public BadRequestException(String message) {
        super(message);
    }
}
