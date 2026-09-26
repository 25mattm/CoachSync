package com.coachsync.service;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.FitnessTestResult;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.FitnessTestResultRepository;
import com.coachsync.web.dto.FitnessTestRequest;
import com.coachsync.web.dto.FitnessTestResponse;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

/** Fitness-test CRUD. An omitted/blank unit defaults to "seconds" (matches the app). */
@Service
public class FitnessTestResultService {

    private static final String DEFAULT_UNIT = "seconds";

    private final FitnessTestResultRepository tests;
    private final AthleteRepository athletes;

    public FitnessTestResultService(FitnessTestResultRepository tests, AthleteRepository athletes) {
        this.tests = tests;
        this.athletes = athletes;
    }

    @Transactional(readOnly = true)
    public List<FitnessTestResponse> listForAthlete(UUID athleteId) {
        if (!athletes.existsById(athleteId)) {
            throw new NotFoundException("No athlete with id " + athleteId);
        }
        return tests.findByAthleteId(athleteId).stream().map(FitnessTestResponse::from).toList();
    }

    @Transactional(readOnly = true)
    public FitnessTestResponse get(UUID id) {
        return FitnessTestResponse.from(getTest(id));
    }

    @Transactional
    public FitnessTestResponse create(UUID athleteId, FitnessTestRequest request) {
        Athlete athlete = athletes.findById(athleteId)
                .orElseThrow(() -> new NotFoundException("No athlete with id " + athleteId));
        if (request.id() != null) {
            var existing = tests.findById(request.id());
            if (existing.isPresent()) {
                FitnessTestResult managed = existing.get();
                // An id already stored under a different athlete is a collision, not an upsert: updating
                // it here would leave the row on that other athlete while reporting success for this one.
                if (!managed.getAthlete().getId().equals(athleteId)) {
                    throw new ConflictException("A record with id " + request.id() + " already exists for another athlete.");
                }
                if (SyncTimestamps.isStale(managed, request.updatedAt())) {
                    return FitnessTestResponse.from(managed);  // re-sent insert is older than the stored row — last-write-wins
                }
                // Update the stored row in place — never new+save() (merge would reset the server-owned createdAt).
                apply(request, managed);
                return FitnessTestResponse.from(tests.save(managed));
            }
        }
        FitnessTestResult test = new FitnessTestResult();
        if (request.id() != null) {
            test.setId(request.id());
        }
        test.setAthlete(athlete);
        apply(request, test);
        return FitnessTestResponse.from(tests.save(test));
    }

    @Transactional
    public FitnessTestResponse update(UUID id, FitnessTestRequest request) {
        FitnessTestResult test = getTest(id);
        if (SyncTimestamps.isStale(test, request.updatedAt())) {
            return FitnessTestResponse.from(test);
        }
        apply(request, test);
        return FitnessTestResponse.from(tests.save(test));
    }

    @Transactional
    public void delete(UUID id) {
        tests.delete(getTest(id));
    }

    private FitnessTestResult getTest(UUID id) {
        return tests.findById(id)
                .orElseThrow(() -> new NotFoundException("No fitness test with id " + id));
    }

    private void apply(FitnessTestRequest request, FitnessTestResult test) {
        test.setTestType(request.testType());
        test.setResult(request.result());
        test.setUnit(request.unit() != null && !request.unit().isBlank() ? request.unit() : DEFAULT_UNIT);
        test.setTestDate(request.testDate());
        test.setNotes(request.notes());
        test.setUpdatedAt(SyncTimestamps.resolve(request.updatedAt()));
    }
}
