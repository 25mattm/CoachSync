package com.coachsync.web.dto;

import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.enums.BlockType;
import com.coachsync.domain.enums.TrainingZone;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Create/update payload for a session block. Full-replace (PUT). The optional
 * numeric/flag fields default when omitted ({@code repetitionCount}/{@code setCount}
 * → 1, {@code sortOrder} → 0, {@code requiresTimeEntry} → true). For pyramids the
 * client supplies {@code repetitionCount} already equal to pattern × sets.
 */
public record BlockRequest(
        UUID id,
        @NotBlank @Size(max = 255) String blockName,
        @NotNull BlockType blockType,
        @PositiveOrZero Integer sortOrder,
        @Min(1) @Max(SessionBlock.MAX_REPETITION_COUNT) Integer repetitionCount,
        @Min(1) @Max(SessionBlock.MAX_SET_COUNT) Integer setCount,
        @PositiveOrZero Double targetDistanceMetres,
        @PositiveOrZero Double distanceKm,
        @PositiveOrZero Integer restIntervalSeconds,
        @PositiveOrZero Integer durationSeconds,
        Boolean requiresTimeEntry,
        TrainingZone trainingZone,
        @Size(max = 255) String drillName,
        @Size(max = 255) String coachNote,
        @Size(max = SessionBlock.MAX_PATTERN_LENGTH)
        List<@NotNull @Positive @Max(SessionBlock.MAX_REP_DURATION_SEC) Integer> prescribedRepDurationsSec,
        Instant updatedAt) {
}
