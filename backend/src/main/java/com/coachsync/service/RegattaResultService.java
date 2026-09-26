package com.coachsync.service;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.RegattaResult;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.RegattaResultRepository;
import com.coachsync.web.dto.RegattaResultRequest;
import com.coachsync.web.dto.RegattaResultResponse;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

/** Regatta-result CRUD. Response mapping reads only scalars + the athlete id. */
@Service
public class RegattaResultService {

    private final RegattaResultRepository results;
    private final AthleteRepository athletes;

    public RegattaResultService(RegattaResultRepository results, AthleteRepository athletes) {
        this.results = results;
        this.athletes = athletes;
    }

    @Transactional(readOnly = true)
    public List<RegattaResultResponse> listForAthlete(UUID athleteId) {
        if (!athletes.existsById(athleteId)) {
            throw new NotFoundException("No athlete with id " + athleteId);
        }
        return results.findByAthleteId(athleteId).stream().map(RegattaResultResponse::from).toList();
    }

    @Transactional(readOnly = true)
    public RegattaResultResponse get(UUID id) {
        return RegattaResultResponse.from(getResult(id));
    }

    @Transactional
    public RegattaResultResponse create(UUID athleteId, RegattaResultRequest request) {
        Athlete athlete = athletes.findById(athleteId)
                .orElseThrow(() -> new NotFoundException("No athlete with id " + athleteId));
        if (request.id() != null) {
            var existing = results.findById(request.id());
            if (existing.isPresent()) {
                RegattaResult managed = existing.get();
                // An id already stored under a different athlete is a collision, not an upsert: updating
                // it here would leave the row on that other athlete while reporting success for this one.
                if (!managed.getAthlete().getId().equals(athleteId)) {
                    throw new ConflictException("A record with id " + request.id() + " already exists for another athlete.");
                }
                if (SyncTimestamps.isStale(managed, request.updatedAt())) {
                    return RegattaResultResponse.from(managed);  // re-sent insert is older than the stored row — last-write-wins
                }
                // Update the stored row in place — never new+save() (merge would reset the server-owned createdAt).
                apply(request, managed);
                return RegattaResultResponse.from(results.save(managed));
            }
        }
        RegattaResult result = new RegattaResult();
        if (request.id() != null) {
            result.setId(request.id());
        }
        result.setAthlete(athlete);
        apply(request, result);
        return RegattaResultResponse.from(results.save(result));
    }

    @Transactional
    public RegattaResultResponse update(UUID id, RegattaResultRequest request) {
        RegattaResult result = getResult(id);
        if (SyncTimestamps.isStale(result, request.updatedAt())) {
            return RegattaResultResponse.from(result);
        }
        apply(request, result);
        return RegattaResultResponse.from(results.save(result));
    }

    @Transactional
    public void delete(UUID id) {
        results.delete(getResult(id));
    }

    private RegattaResult getResult(UUID id) {
        return results.findById(id)
                .orElseThrow(() -> new NotFoundException("No regatta result with id " + id));
    }

    private void apply(RegattaResultRequest request, RegattaResult result) {
        result.setRegattaName(request.regattaName());
        result.setLocation(request.location());
        result.setRegattaDate(request.regattaDate());
        result.setEventDistanceMetres(request.eventDistanceMetres());
        result.setPlacement(request.placement());
        result.setTotalCompetitors(request.totalCompetitors());
        result.setResultTimeMs(request.resultTimeMs());
        result.setNotes(request.notes());
        result.setUpdatedAt(SyncTimestamps.resolve(request.updatedAt()));
    }
}
