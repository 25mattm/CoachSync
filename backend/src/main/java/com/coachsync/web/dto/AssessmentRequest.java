package com.coachsync.web.dto;

import com.coachsync.domain.enums.DevelopmentStage;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/**
 * Create/update payload for a technical assessment. Full-replace (PUT): an
 * omitted {@code stage} resets to INITIATION and {@code ratings} fully replaces
 * the prior set. {@code ratings} may be null/empty (an assessment can start with
 * no scored factors).
 */
public record AssessmentRequest(
        UUID id,
        @NotNull LocalDate date,
        DevelopmentStage stage,
        String overallNotes,
        @Valid List<RatingRequest> ratings,
        Instant updatedAt) {
}
