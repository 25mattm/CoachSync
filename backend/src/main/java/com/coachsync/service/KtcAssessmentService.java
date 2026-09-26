package com.coachsync.service;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.KtcAssessment;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.KtcAssessmentRepository;
import com.coachsync.web.dto.KtcRequest;
import com.coachsync.web.dto.KtcResponse;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

/** KTC-assessment CRUD. Response mapping reads only scalars + the athlete id. */
@Service
public class KtcAssessmentService {

    private final KtcAssessmentRepository ktc;
    private final AthleteRepository athletes;

    public KtcAssessmentService(KtcAssessmentRepository ktc, AthleteRepository athletes) {
        this.ktc = ktc;
        this.athletes = athletes;
    }

    @Transactional(readOnly = true)
    public List<KtcResponse> listForAthlete(UUID athleteId) {
        if (!athletes.existsById(athleteId)) {
            throw new NotFoundException("No athlete with id " + athleteId);
        }
        return ktc.findByAthleteId(athleteId).stream().map(KtcResponse::from).toList();
    }

    @Transactional(readOnly = true)
    public KtcResponse get(UUID id) {
        return KtcResponse.from(getKtc(id));
    }

    @Transactional
    public KtcResponse create(UUID athleteId, KtcRequest request) {
        Athlete athlete = athletes.findById(athleteId)
                .orElseThrow(() -> new NotFoundException("No athlete with id " + athleteId));
        if (request.id() != null) {
            var existing = ktc.findById(request.id());
            if (existing.isPresent()) {
                KtcAssessment managed = existing.get();
                // An id already stored under a different athlete is a collision, not an upsert: updating
                // it here would leave the row on that other athlete while reporting success for this one.
                if (!managed.getAthlete().getId().equals(athleteId)) {
                    throw new ConflictException("A record with id " + request.id() + " already exists for another athlete.");
                }
                if (SyncTimestamps.isStale(managed, request.updatedAt())) {
                    return KtcResponse.from(managed);  // re-sent insert is older than the stored row — last-write-wins
                }
                // Update the stored row in place — never new+save() (merge would reset the server-owned createdAt).
                apply(request, managed);
                return KtcResponse.from(ktc.save(managed));
            }
        }
        KtcAssessment assessment = new KtcAssessment();
        if (request.id() != null) {
            assessment.setId(request.id());
        }
        assessment.setAthlete(athlete);
        apply(request, assessment);
        return KtcResponse.from(ktc.save(assessment));
    }

    @Transactional
    public KtcResponse update(UUID id, KtcRequest request) {
        KtcAssessment assessment = getKtc(id);
        if (SyncTimestamps.isStale(assessment, request.updatedAt())) {
            return KtcResponse.from(assessment);
        }
        apply(request, assessment);
        return KtcResponse.from(ktc.save(assessment));
    }

    @Transactional
    public void delete(UUID id) {
        ktc.delete(getKtc(id));
    }

    private KtcAssessment getKtc(UUID id) {
        return ktc.findById(id)
                .orElseThrow(() -> new NotFoundException("No KTC assessment with id " + id));
    }

    private void apply(KtcRequest request, KtcAssessment assessment) {
        assessment.setDate(request.date());
        assessment.setWindow(request.window());
        assessment.setSetupRecoveryScore(request.setupRecoveryScore());
        assessment.setCatchScore(request.catchScore());
        assessment.setPropulsionDrawScore(request.propulsionDrawScore());
        assessment.setExitScore(request.exitScore());
        assessment.setNotes(request.notes());
        assessment.setUpdatedAt(SyncTimestamps.resolve(request.updatedAt()));
    }
}
