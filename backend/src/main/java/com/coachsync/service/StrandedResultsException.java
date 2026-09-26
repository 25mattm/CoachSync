package com.coachsync.service;

import java.util.UUID;

/**
 * Thrown when a block edit would strand recorded rep results — i.e. shrink a
 * block's capacity below an already-filled rep, or switch it to a type that
 * captures no per-rep data while filled slots exist. Mirrors the iOS save guard
 * (AddBlockSheet.commit): recorded coaching data is never silently destroyed.
 *
 * <p>The block-update endpoint will translate this to HTTP 409 in the controller
 * vertical.
 */
public class StrandedResultsException extends ConflictException {

    public StrandedResultsException(UUID blockId, int highestFilledRep, int newCapacity) {
        super("Session block " + blockId + " has recorded results up to rep "
                + highestFilledRep + "; cannot reduce its capacity to " + newCapacity
                + " without stranding them. Clear those results first.");
    }
}
