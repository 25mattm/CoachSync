package com.coachsync.service;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.HeightRecord;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.HeightRecordRepository;
import com.coachsync.web.dto.HeightRecordRequest;
import com.coachsync.web.dto.HeightRecordResponse;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

/** Height-record CRUD (PHV tracking data). */
@Service
public class HeightRecordService {

    private final HeightRecordRepository heights;
    private final AthleteRepository athletes;

    public HeightRecordService(HeightRecordRepository heights, AthleteRepository athletes) {
        this.heights = heights;
        this.athletes = athletes;
    }

    @Transactional(readOnly = true)
    public List<HeightRecordResponse> listForAthlete(UUID athleteId) {
        if (!athletes.existsById(athleteId)) {
            throw new NotFoundException("No athlete with id " + athleteId);
        }
        return heights.findByAthleteId(athleteId).stream().map(HeightRecordResponse::from).toList();
    }

    @Transactional(readOnly = true)
    public HeightRecordResponse get(UUID id) {
        return HeightRecordResponse.from(getHeight(id));
    }

    @Transactional
    public HeightRecordResponse create(UUID athleteId, HeightRecordRequest request) {
        Athlete athlete = athletes.findById(athleteId)
                .orElseThrow(() -> new NotFoundException("No athlete with id " + athleteId));
        if (request.id() != null) {
            var existing = heights.findById(request.id());
            if (existing.isPresent()) {
                HeightRecord managed = existing.get();
                // An id already stored under a different athlete is a collision, not an upsert: updating
                // it here would leave the row on that other athlete while reporting success for this one.
                if (!managed.getAthlete().getId().equals(athleteId)) {
                    throw new ConflictException("A record with id " + request.id() + " already exists for another athlete.");
                }
                if (SyncTimestamps.isStale(managed, request.updatedAt())) {
                    return HeightRecordResponse.from(managed);  // re-sent insert is older than the stored row — last-write-wins
                }
                // Update the stored row in place — never new+save() (merge would reset the server-owned createdAt).
                apply(request, managed);
                return HeightRecordResponse.from(heights.save(managed));
            }
        }
        HeightRecord height = new HeightRecord();
        if (request.id() != null) {
            height.setId(request.id());
        }
        height.setAthlete(athlete);
        apply(request, height);
        return HeightRecordResponse.from(heights.save(height));
    }

    @Transactional
    public HeightRecordResponse update(UUID id, HeightRecordRequest request) {
        HeightRecord height = getHeight(id);
        if (SyncTimestamps.isStale(height, request.updatedAt())) {
            return HeightRecordResponse.from(height);
        }
        apply(request, height);
        return HeightRecordResponse.from(heights.save(height));
    }

    @Transactional
    public void delete(UUID id) {
        heights.delete(getHeight(id));
    }

    private HeightRecord getHeight(UUID id) {
        return heights.findById(id)
                .orElseThrow(() -> new NotFoundException("No height record with id " + id));
    }

    private void apply(HeightRecordRequest request, HeightRecord height) {
        height.setHeightCm(request.heightCm());
        height.setDate(request.date());
        height.setUpdatedAt(SyncTimestamps.resolve(request.updatedAt()));
    }
}
