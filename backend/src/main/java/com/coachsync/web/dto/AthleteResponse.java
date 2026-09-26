package com.coachsync.web.dto;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.enums.DevelopmentStage;
import com.coachsync.domain.enums.Gender;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/** Athlete representation returned by the API. */
public record AthleteResponse(
        UUID id,
        String firstName,
        String lastName,
        LocalDate dateOfBirth,
        Gender gender,
        String guardianName,
        String guardianPhone,
        String guardianEmail,
        boolean active,
        DevelopmentStage developmentStage,
        Instant createdAt,
        Instant updatedAt) {

    public static AthleteResponse from(Athlete a) {
        return new AthleteResponse(
                a.getId(), a.getFirstName(), a.getLastName(), a.getDateOfBirth(),
                a.getGender(), a.getGuardianName(), a.getGuardianPhone(), a.getGuardianEmail(),
                a.isActive(), a.getDevelopmentStage(), a.getCreatedAt(), a.getUpdatedAt());
    }
}
