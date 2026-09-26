package com.coachsync.web.dto;

import com.coachsync.domain.KtcAssessment;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/** A KTC assessment with its four scores and computed average. */
public record KtcResponse(
        UUID id,
        UUID athleteId,
        LocalDate date,
        String window,
        int setupRecoveryScore,
        int catchScore,
        int propulsionDrawScore,
        int exitScore,
        double averageScore,
        String notes,
        Instant createdAt,
        Instant updatedAt) {

    public static KtcResponse from(KtcAssessment k) {
        double average = (k.getSetupRecoveryScore() + k.getCatchScore()
                + k.getPropulsionDrawScore() + k.getExitScore()) / 4.0;
        return new KtcResponse(
                k.getId(), k.getAthlete().getId(), k.getDate(), k.getWindow(),
                k.getSetupRecoveryScore(), k.getCatchScore(), k.getPropulsionDrawScore(), k.getExitScore(),
                average, k.getNotes(), k.getCreatedAt(), k.getUpdatedAt());
    }
}
