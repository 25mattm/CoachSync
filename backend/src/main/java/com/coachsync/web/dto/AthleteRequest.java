package com.coachsync.web.dto;

import com.coachsync.domain.enums.DevelopmentStage;
import com.coachsync.domain.enums.Gender;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Past;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/**
 * Create/update payload for an athlete. {@code gender}, the guardian fields, and
 * {@code developmentStage} are optional. This is a full-replace payload (PUT): an
 * omitted optional field is cleared, and an omitted {@code developmentStage}
 * resets to INITIATION. ({@code isActive} is managed via {@code PATCH /{id}/active}.)
 * String fields are capped at the column length (255) so over-long input is a 400,
 * not a downstream DB error.
 */
public record AthleteRequest(
        UUID id,
        @NotBlank @Size(max = 255) String firstName,
        @NotBlank @Size(max = 255) String lastName,
        @NotNull @Past LocalDate dateOfBirth,
        Gender gender,
        @Size(max = 255) String guardianName,
        @Size(max = 255) String guardianPhone,
        @Email @Size(max = 255) String guardianEmail,
        DevelopmentStage developmentStage,
        Boolean active,
        Instant updatedAt) {
}
