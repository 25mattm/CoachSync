package com.coachsync.service;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.TechnicalAssessment;
import com.coachsync.domain.TechnicalRating;
import com.coachsync.domain.enums.DevelopmentStage;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.TechnicalAssessmentRepository;
import com.coachsync.web.dto.AssessmentRequest;
import com.coachsync.web.dto.AssessmentResponse;
import com.coachsync.web.dto.RatingRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

/**
 * Technical-assessment CRUD. Ratings are a single-owner aggregate: create builds
 * them with the assessment, and PUT fully replaces them (orphanRemoval deletes
 * the dropped ones). Response mapping happens inside the transaction (lazy
 * ratings).
 */
@Service
public class TechnicalAssessmentService {

    private final TechnicalAssessmentRepository assessments;
    private final AthleteRepository athletes;

    public TechnicalAssessmentService(TechnicalAssessmentRepository assessments, AthleteRepository athletes) {
        this.assessments = assessments;
        this.athletes = athletes;
    }

    @Transactional(readOnly = true)
    public List<AssessmentResponse> listForAthlete(UUID athleteId) {
        if (!athletes.existsById(athleteId)) {
            throw new NotFoundException("No athlete with id " + athleteId);
        }
        return assessments.findByAthleteId(athleteId).stream().map(AssessmentResponse::from).toList();
    }

    @Transactional(readOnly = true)
    public AssessmentResponse get(UUID id) {
        return AssessmentResponse.from(getAssessment(id));
    }

    @Transactional
    public AssessmentResponse create(UUID athleteId, AssessmentRequest request) {
        Athlete athlete = athletes.findById(athleteId)
                .orElseThrow(() -> new NotFoundException("No athlete with id " + athleteId));
        if (request.id() != null) {
            var existing = assessments.findById(request.id());
            if (existing.isPresent()) {
                TechnicalAssessment managed = existing.get();
                // An id already stored under a different athlete is a collision, not an upsert: updating
                // it here would leave the row on that other athlete while reporting success for this one.
                if (!managed.getAthlete().getId().equals(athleteId)) {
                    throw new ConflictException("A record with id " + request.id() + " already exists for another athlete.");
                }
                if (SyncTimestamps.isStale(managed, request.updatedAt())) {
                    return AssessmentResponse.from(managed);  // re-sent insert is older than the stored row — last-write-wins
                }
                // Update the stored row in place — never new+save() (merge would reset the server-owned createdAt).
                apply(request, managed);
                return AssessmentResponse.from(assessments.save(managed));
            }
        }
        TechnicalAssessment assessment = new TechnicalAssessment();
        if (request.id() != null) {
            assessment.setId(request.id());
        }
        assessment.setAthlete(athlete);
        apply(request, assessment);
        return AssessmentResponse.from(assessments.save(assessment));
    }

    @Transactional
    public AssessmentResponse update(UUID id, AssessmentRequest request) {
        TechnicalAssessment assessment = getAssessment(id);
        if (SyncTimestamps.isStale(assessment, request.updatedAt())) {
            return AssessmentResponse.from(assessment);
        }
        apply(request, assessment);
        return AssessmentResponse.from(assessments.save(assessment));
    }

    @Transactional
    public void delete(UUID id) {
        assessments.delete(getAssessment(id));
    }

    private TechnicalAssessment getAssessment(UUID id) {
        return assessments.findById(id)
                .orElseThrow(() -> new NotFoundException("No assessment with id " + id));
    }

    private void apply(AssessmentRequest request, TechnicalAssessment assessment) {
        assessment.setDate(request.date());
        assessment.setStage(request.stage() != null ? request.stage() : DevelopmentStage.INITIATION);
        assessment.setOverallNotes(request.overallNotes());
        // Full-replace the ratings: clearing the managed collection lets
        // orphanRemoval delete the dropped rows before the new ones are added.
        assessment.getRatings().clear();
        if (request.ratings() != null) {
            for (RatingRequest rr : request.ratings()) {
                TechnicalRating rating = new TechnicalRating();
                rating.setAssessment(assessment);
                rating.setCategory(rr.category());
                rating.setFactor(rr.factor());
                rating.setScore(rr.score());
                rating.setComment(rr.comment());
                assessment.getRatings().add(rating);
            }
        }
        assessment.setUpdatedAt(SyncTimestamps.resolve(request.updatedAt()));
    }
}
