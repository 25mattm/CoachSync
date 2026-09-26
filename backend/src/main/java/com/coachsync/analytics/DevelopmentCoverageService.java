package com.coachsync.analytics;

import com.coachsync.domain.DevelopmentNote;
import com.coachsync.domain.TechnicalAssessment;
import com.coachsync.domain.TechnicalRating;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.DevelopmentNoteRepository;
import com.coachsync.repository.TechnicalAssessmentRepository;
import com.coachsync.service.NotFoundException;
import com.coachsync.web.dto.DevelopmentCoverageEntry;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.UUID;

/**
 * Development-coverage analysis — the backend port of the iOS
 * {@code Athlete.developmentCoverage}. For the focus areas of an athlete's
 * latest technical assessment (factors scoring &le; 2), counts how many recent
 * journal entries carry a tag matching the focus area, surfacing uncovered gaps.
 */
@Service
public class DevelopmentCoverageService {

    /** Rolling window (days) of journal entries that can cover a focus area. */
    private static final int COVERAGE_WINDOW_DAYS = 60;
    /** A factor at/below this score is a development focus area. */
    private static final int FOCUS_AREA_MAX_SCORE = 2;

    private final AthleteRepository athletes;
    private final TechnicalAssessmentRepository assessments;
    private final DevelopmentNoteRepository journal;
    private final Clock clock;

    public DevelopmentCoverageService(AthleteRepository athletes,
                                      TechnicalAssessmentRepository assessments,
                                      DevelopmentNoteRepository journal,
                                      Clock clock) {
        this.athletes = athletes;
        this.assessments = assessments;
        this.journal = journal;
        this.clock = clock;
    }

    @Transactional(readOnly = true)
    public List<DevelopmentCoverageEntry> coverage(UUID athleteId) {
        if (!athletes.existsById(athleteId)) {
            throw new NotFoundException("No athlete with id " + athleteId);
        }

        // Latest assessment by date (tie-break createdAt) — the focus-area source.
        Optional<TechnicalAssessment> latest = assessments.findByAthleteId(athleteId).stream()
                .max(Comparator.comparing(TechnicalAssessment::getDate)
                        .thenComparing(TechnicalAssessment::getCreatedAt));
        if (latest.isEmpty()) {
            return List.of();
        }

        // Journal entries inside the rolling window can "cover" a focus area.
        LocalDate cutoff = LocalDate.now(clock).minusDays(COVERAGE_WINDOW_DAYS);
        List<DevelopmentNote> recentNotes = journal.findByAthleteId(athleteId).stream()
                .filter(n -> !n.getDate().isBefore(cutoff))
                .toList();

        return latest.get().getRatings().stream()
                .filter(r -> r.getScore() <= FOCUS_AREA_MAX_SCORE)
                .sorted(Comparator.comparing(TechnicalRating::getCategory))
                .map(rating -> {
                    long noteCount = recentNotes.stream().filter(n -> covers(n, rating)).count();
                    return new DevelopmentCoverageEntry(
                            rating.getCategory(), rating.getFactor(), rating.getScore(),
                            noteCount, noteCount > 0);
                })
                .toList();
    }

    /**
     * True when any of the note's tags appears (case-insensitively) in the
     * rating's "factor + category" text. Mirrors iOS {@code matchesDevelopmentTag}.
     */
    private static boolean covers(DevelopmentNote note, TechnicalRating rating) {
        String haystack = (rating.getFactor() + " " + rating.getCategory()).toLowerCase(Locale.ROOT);
        return note.getTags().stream()
                .anyMatch(tag -> !tag.isEmpty() && haystack.contains(tag.toLowerCase(Locale.ROOT)));
    }
}
