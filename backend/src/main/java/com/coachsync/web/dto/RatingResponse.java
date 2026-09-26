package com.coachsync.web.dto;

import com.coachsync.domain.TechnicalRating;

import java.time.Instant;
import java.util.UUID;

/** One scored factor in an assessment response. */
public record RatingResponse(
        UUID id, String category, String factor, int score, String comment,
        Instant updatedAt) {

    public static RatingResponse from(TechnicalRating r) {
        return new RatingResponse(
                r.getId(), r.getCategory(), r.getFactor(), r.getScore(), r.getComment(),
                r.getUpdatedAt());
    }
}
