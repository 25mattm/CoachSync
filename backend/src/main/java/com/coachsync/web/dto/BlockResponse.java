package com.coachsync.web.dto;

import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.enums.BlockType;
import com.coachsync.domain.enums.TrainingZone;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Session-block representation. Built inside a transaction — {@code sessionId}
 * comes from the lazy session proxy's id and {@code prescribedRepDurationsSec}
 * is a lazy element collection.
 */
public record BlockResponse(
        UUID id,
        UUID sessionId,
        String blockName,
        BlockType blockType,
        int sortOrder,
        int repetitionCount,
        int setCount,
        Double targetDistanceMetres,
        Double distanceKm,
        Integer restIntervalSeconds,
        Integer durationSeconds,
        boolean requiresTimeEntry,
        TrainingZone trainingZone,
        String drillName,
        String coachNote,
        List<Integer> prescribedRepDurationsSec,
        Instant updatedAt) {

    public static BlockResponse from(SessionBlock b) {
        return new BlockResponse(
                b.getId(), b.getSession().getId(), b.getBlockName(), b.getBlockType(),
                b.getSortOrder(), b.getRepetitionCount(), b.getSetCount(),
                b.getTargetDistanceMetres(), b.getDistanceKm(), b.getRestIntervalSeconds(),
                b.getDurationSeconds(), b.isRequiresTimeEntry(), b.getTrainingZone(),
                b.getDrillName(), b.getCoachNote(), List.copyOf(b.getPrescribedRepDurationsSec()),
                b.getUpdatedAt());
    }
}
