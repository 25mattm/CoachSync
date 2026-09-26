package com.coachsync.service;

import com.coachsync.domain.enums.AttendanceStatus;
import com.coachsync.domain.enums.RepEntryStatus;
import com.coachsync.repository.AthleteNoteRepository;
import com.coachsync.repository.AttendanceRecordRepository;
import com.coachsync.repository.DevelopmentNoteRepository;
import com.coachsync.repository.FitnessTestResultRepository;
import com.coachsync.repository.HeightRecordRepository;
import com.coachsync.repository.KtcAssessmentRepository;
import com.coachsync.repository.PerformanceRecordRepository;
import com.coachsync.repository.RegattaResultRepository;
import com.coachsync.repository.TechnicalAssessmentRepository;
import org.springframework.stereotype.Component;

import java.util.UUID;

/**
 * Decides whether an athlete has any recorded history that locks them against
 * deletion. "History" = data a coach actually recorded — present attendance, a
 * filled rep result (a time / DNS / DNF), a note, a technical assessment, a KTC,
 * a journal entry, a regatta result, a fitness test, or a height measurement.
 * Roster artifacts (absent/excused attendance, pending no-time slots) do NOT lock.
 *
 * <p>Extracted from {@code AthleteService} so its delete path depends on one
 * collaborator rather than every history repository.
 */
@Component
public class AthleteHistoryGuard {

    private final AttendanceRecordRepository attendance;
    private final PerformanceRecordRepository performance;
    private final AthleteNoteRepository notes;
    private final TechnicalAssessmentRepository assessments;
    private final KtcAssessmentRepository ktc;
    private final DevelopmentNoteRepository journal;
    private final RegattaResultRepository regatta;
    private final FitnessTestResultRepository fitness;
    private final HeightRecordRepository heights;

    public AthleteHistoryGuard(AttendanceRecordRepository attendance,
                               PerformanceRecordRepository performance,
                               AthleteNoteRepository notes,
                               TechnicalAssessmentRepository assessments,
                               KtcAssessmentRepository ktc,
                               DevelopmentNoteRepository journal,
                               RegattaResultRepository regatta,
                               FitnessTestResultRepository fitness,
                               HeightRecordRepository heights) {
        this.attendance = attendance;
        this.performance = performance;
        this.notes = notes;
        this.assessments = assessments;
        this.ktc = ktc;
        this.journal = journal;
        this.regatta = regatta;
        this.fitness = fitness;
        this.heights = heights;
    }

    /** True if the athlete has any recorded history (so they cannot be deleted). */
    public boolean hasRecordedHistory(UUID athleteId) {
        return attendance.existsByAthleteIdAndStatus(athleteId, AttendanceStatus.PRESENT)
                || performance.existsByAthleteIdAndStatusNot(athleteId, RepEntryStatus.PENDING)
                || performance.existsByAthleteIdAndRecordedTimeMsIsNotNull(athleteId)
                || notes.existsByAthleteId(athleteId)
                || assessments.existsByAthleteId(athleteId)
                || ktc.existsByAthleteId(athleteId)
                || journal.existsByAthleteId(athleteId)
                || regatta.existsByAthleteId(athleteId)
                || fitness.existsByAthleteId(athleteId)
                || heights.existsByAthleteId(athleteId);
    }
}
