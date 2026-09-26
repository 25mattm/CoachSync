package com.coachsync.web.dto;

import com.coachsync.domain.TechnicalAssessment;
import com.coachsync.domain.TechnicalRating;
import com.coachsync.domain.enums.DevelopmentStage;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/**
 * A technical assessment with its ratings and computed average. Built inside a
 * transaction (the lazy {@code ratings}/{@code athlete} associations are read).
 */
public record AssessmentResponse(
        UUID id,
        UUID athleteId,
        LocalDate date,
        DevelopmentStage stage,
        String overallNotes,
        double averageScore,
        Instant createdAt,
        Instant updatedAt,
        List<RatingResponse> ratings) {

    public static AssessmentResponse from(TechnicalAssessment a) {
        List<TechnicalRating> ratings = a.getRatings();
        double average = ratings.isEmpty()
                ? 0.0
                : ratings.stream().mapToInt(TechnicalRating::getScore).sum() / (double) ratings.size();
        return new AssessmentResponse(
                a.getId(), a.getAthlete().getId(), a.getDate(), a.getStage(),
                a.getOverallNotes(), average, a.getCreatedAt(), a.getUpdatedAt(),
                ratings.stream().map(RatingResponse::from).toList());
    }
}
