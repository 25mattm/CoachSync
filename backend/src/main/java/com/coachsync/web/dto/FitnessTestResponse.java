package com.coachsync.web.dto;

import com.coachsync.domain.FitnessTestResult;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/** A fitness-test result. */
public record FitnessTestResponse(
        UUID id,
        UUID athleteId,
        String testType,
        double result,
        String unit,
        LocalDate testDate,
        String notes,
        Instant createdAt,
        Instant updatedAt) {

    public static FitnessTestResponse from(FitnessTestResult t) {
        return new FitnessTestResponse(
                t.getId(), t.getAthlete().getId(), t.getTestType(), t.getResult(),
                t.getUnit(), t.getTestDate(), t.getNotes(), t.getCreatedAt(), t.getUpdatedAt());
    }
}
