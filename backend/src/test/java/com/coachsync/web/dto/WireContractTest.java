package com.coachsync.web.dto;

import com.coachsync.domain.enums.AttendanceStatus;
import com.coachsync.domain.enums.BlockType;
import com.coachsync.domain.enums.DevelopmentStage;
import com.coachsync.domain.enums.Gender;
import com.coachsync.domain.enums.RepEntryStatus;
import com.coachsync.domain.enums.SessionStatus;
import com.coachsync.domain.enums.TrainingZone;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import tools.jackson.databind.ObjectMapper;

import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * Cross-stack wire contract (review finding F13, extended by G19). Pins the JSON field names of
 * every response DTO the iOS app's sync pull decodes (see {@code CoachSync/Sync/SyncDTOs.swift}).
 * The app hand-writes those {@code Decodable} structs and its own test JSON, so nothing but this
 * test couples the two sides: a backend field rename/retype would compile and pass every backend
 * test yet silently break the app at runtime. If an expected set below changes, update the
 * matching Swift {@code *DTO} in lockstep.
 */
@SpringBootTest
class WireContractTest {

    // The Spring-configured Jackson 3 mapper — resolves java.time serialization the same way the live
    // API does, so the serialized property names are exactly what the app receives on the wire.
    @Autowired private ObjectMapper json;

    @SuppressWarnings("unchecked")
    private Set<String> wireFields(Object dto) {
        Map<String, Object> map = json.convertValue(dto, Map.class);
        return map.keySet();
    }

    @Test
    void athleteResponseMatchesAppAthleteDTO() {
        var dto = new AthleteResponse(UUID.randomUUID(), "Ada", "Lovelace", LocalDate.of(2010, 6, 15),
                Gender.FEMALE, "Guardian", "555-0100", "g@example.com", true,
                DevelopmentStage.INITIATION, Instant.now(), Instant.now());
        assertEquals(Set.of("id", "firstName", "lastName", "dateOfBirth", "gender", "guardianName",
                        "guardianPhone", "guardianEmail", "active", "developmentStage", "createdAt", "updatedAt"),
                wireFields(dto),
                "AthleteResponse wire shape must match the app's AthleteDTO (CoachSync/Sync/SyncDTOs.swift)");
    }

    @Test
    void sessionResponseMatchesAppSessionDTO() {
        var dto = new SessionResponse(UUID.randomUUID(), "Tuesday", LocalDate.of(2026, 6, 10),
                LocalDateTime.of(2026, 6, 10, 17, 0), LocalDateTime.of(2026, 6, 10, 18, 30),
                SessionStatus.OPEN, "sunny", "team note", "session note", "cue", false,
                UUID.randomUUID(), UUID.randomUUID(), Instant.now(), Instant.now());
        assertEquals(Set.of("id", "sessionName", "scheduledDate", "startTime", "endTime", "status",
                        "weatherNote", "teamNote", "sessionNote", "mfCue", "archived", "coachId", "teamId",
                        "createdAt", "updatedAt"),
                wireFields(dto),
                "SessionResponse wire shape must match the app's SessionDTO (CoachSync/Sync/SyncDTOs.swift)");
    }

    @Test
    void blockResponseMatchesAppBlockDTO() {
        var dto = new BlockResponse(UUID.randomUUID(), UUID.randomUUID(), "Paddle", BlockType.PADDLE_DISTANCE,
                0, 3, 1, 500.0, 2.0, 60, 120, true, TrainingZone.GA_1, "drill", "note",
                List.of(30, 40, 50), Instant.now());
        assertEquals(Set.of("id", "sessionId", "blockName", "blockType", "sortOrder", "repetitionCount",
                        "setCount", "targetDistanceMetres", "distanceKm", "restIntervalSeconds",
                        "durationSeconds", "requiresTimeEntry", "trainingZone", "drillName", "coachNote",
                        "prescribedRepDurationsSec", "updatedAt"),
                wireFields(dto),
                "BlockResponse wire shape must match the app's BlockDTO (CoachSync/Sync/SyncDTOs.swift)");
    }

    @Test
    void coachResponseMatchesAppCoachDTO() {
        var dto = new CoachResponse(UUID.randomUUID(), "Pat", "Head Coach", "L3", "#FF0000",
                Instant.now(), Instant.now());
        assertEquals(Set.of("id", "name", "role", "nccpLevel", "colorHex", "createdAt", "updatedAt"),
                wireFields(dto),
                "CoachResponse wire shape must match the app's CoachDTO (CoachSync/Sync/SyncDTOs.swift)");
    }

    @Test
    void teamResponseMatchesAppTeamDTO() {
        var dto = new TeamResponse(UUID.randomUUID(), "U16", "Description", false,
                Instant.now(), Instant.now());
        assertEquals(Set.of("id", "teamName", "teamDescription", "archived", "createdAt", "updatedAt"),
                wireFields(dto),
                "TeamResponse wire shape must match the app's TeamDTO (CoachSync/Sync/SyncDTOs.swift)");
    }

    @Test
    void teamMembershipResponseMatchesAppMembershipDTO() {
        var dto = new TeamMembershipResponse(UUID.randomUUID(), UUID.randomUUID(), "Ada", "Lovelace",
                UUID.randomUUID(), LocalDate.of(2026, 1, 1), null, Instant.now());
        assertEquals(Set.of("id", "athleteId", "athleteFirstName", "athleteLastName", "teamId",
                        "joinedDate", "leftDate", "updatedAt"),
                wireFields(dto),
                "TeamMembershipResponse wire shape must match the app's MembershipDTO (CoachSync/Sync/SyncDTOs.swift)");
    }

    @Test
    void attendanceResponseMatchesAppAttendanceDTO() {
        var dto = new AttendanceResponse(UUID.randomUUID(), UUID.randomUUID(), "Ada", "Lovelace",
                AttendanceStatus.PRESENT, null, Instant.now());
        assertEquals(Set.of("id", "athleteId", "athleteFirstName", "athleteLastName", "status",
                        "absenceReason", "updatedAt"),
                wireFields(dto),
                "AttendanceResponse wire shape must match the app's AttendanceDTO (CoachSync/Sync/SyncDTOs.swift)");
    }

    @Test
    void performanceResponseMatchesAppPerformanceDTO() {
        var dto = new PerformanceResponse(UUID.randomUUID(), UUID.randomUUID(), "Ada", "Lovelace",
                1, 120_000, RepEntryStatus.COMPLETE, Instant.now());
        assertEquals(Set.of("id", "athleteId", "athleteFirstName", "athleteLastName", "repNumber",
                        "recordedTimeMs", "status", "updatedAt"),
                wireFields(dto),
                "PerformanceResponse wire shape must match the app's PerformanceDTO (CoachSync/Sync/SyncDTOs.swift)");
    }

    @Test
    void noteResponseMatchesAppNoteDTO() {
        var dto = new NoteResponse(UUID.randomUUID(), "Great effort", Instant.now(),
                UUID.randomUUID(), "Ada", "Lovelace", UUID.randomUUID(), UUID.randomUUID(),
                UUID.randomUUID(), Instant.now());
        assertEquals(Set.of("id", "noteText", "createdAt", "athleteId", "athleteFirstName",
                        "athleteLastName", "sessionId", "sessionBlockId", "coachId", "updatedAt"),
                wireFields(dto),
                "NoteResponse wire shape must match the app's NoteDTO (CoachSync/Sync/SyncDTOs.swift)");
    }

    @Test
    void assessmentResponseMatchesAppAssessmentDTO() {
        var rating = new RatingResponse(UUID.randomUUID(), "Technique", "Catch", 4, "Good", Instant.now());
        var dto = new AssessmentResponse(UUID.randomUUID(), UUID.randomUUID(), LocalDate.of(2026, 6, 1),
                DevelopmentStage.INITIATION, "Notes", 4.0, Instant.now(), Instant.now(), List.of(rating));
        assertEquals(Set.of("id", "athleteId", "date", "stage", "overallNotes", "averageScore",
                        "createdAt", "updatedAt", "ratings"),
                wireFields(dto),
                "AssessmentResponse wire shape must match the app's AssessmentDTO (CoachSync/Sync/SyncDTOs.swift)");
    }

    @Test
    void ratingResponseMatchesAppRatingDTO() {
        var dto = new RatingResponse(UUID.randomUUID(), "Technique", "Catch", 4, "Good", Instant.now());
        assertEquals(Set.of("id", "category", "factor", "score", "comment", "updatedAt"),
                wireFields(dto),
                "RatingResponse wire shape must match the app's RatingDTO (CoachSync/Sync/SyncDTOs.swift)");
    }

    @Test
    void fitnessTestResponseMatchesAppFitnessTestDTO() {
        var dto = new FitnessTestResponse(UUID.randomUUID(), UUID.randomUUID(), "Broad Jump", 2.1, "m",
                LocalDate.of(2026, 6, 1), "Notes", Instant.now(), Instant.now());
        assertEquals(Set.of("id", "athleteId", "testType", "result", "unit", "testDate", "notes",
                        "createdAt", "updatedAt"),
                wireFields(dto),
                "FitnessTestResponse wire shape must match the app's FitnessTestDTO (CoachSync/Sync/SyncDTOs.swift)");
    }

    @Test
    void regattaResultResponseMatchesAppRegattaResultDTO() {
        var dto = new RegattaResultResponse(UUID.randomUUID(), UUID.randomUUID(), "Regionals", "Lake",
                LocalDate.of(2026, 6, 1), 500, 1, 10, 120_000, "Notes", Instant.now(), Instant.now());
        assertEquals(Set.of("id", "athleteId", "regattaName", "location", "regattaDate",
                        "eventDistanceMetres", "placement", "totalCompetitors", "resultTimeMs", "notes",
                        "createdAt", "updatedAt"),
                wireFields(dto),
                "RegattaResultResponse wire shape must match the app's RegattaResultDTO (CoachSync/Sync/SyncDTOs.swift)");
    }

    @Test
    void journalResponseMatchesAppJournalDTO() {
        var dto = new JournalResponse(UUID.randomUUID(), UUID.randomUUID(), LocalDate.of(2026, 6, 1),
                "Entry text", List.of("Mental"), UUID.randomUUID(), Instant.now(), Instant.now());
        assertEquals(Set.of("id", "athleteId", "date", "text", "tags", "coachId", "createdAt", "updatedAt"),
                wireFields(dto),
                "JournalResponse wire shape must match the app's JournalDTO (CoachSync/Sync/SyncDTOs.swift)");
    }

    @Test
    void ktcResponseMatchesAppKtcDTO() {
        var dto = new KtcResponse(UUID.randomUUID(), UUID.randomUUID(), LocalDate.of(2026, 6, 1),
                "Spring", 3, 4, 3, 4, 3.5, "Notes", Instant.now(), Instant.now());
        assertEquals(Set.of("id", "athleteId", "date", "window", "setupRecoveryScore", "catchScore",
                        "propulsionDrawScore", "exitScore", "averageScore", "notes", "createdAt", "updatedAt"),
                wireFields(dto),
                "KtcResponse wire shape must match the app's KtcDTO (CoachSync/Sync/SyncDTOs.swift)");
    }

    @Test
    void heightRecordResponseMatchesAppHeightRecordDTO() {
        var dto = new HeightRecordResponse(UUID.randomUUID(), UUID.randomUUID(), 165.2,
                LocalDate.of(2026, 6, 1), Instant.now(), Instant.now());
        assertEquals(Set.of("id", "athleteId", "heightCm", "date", "createdAt", "updatedAt"),
                wireFields(dto),
                "HeightRecordResponse wire shape must match the app's HeightRecordDTO (CoachSync/Sync/SyncDTOs.swift)");
    }
}
