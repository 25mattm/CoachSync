package com.coachsync.service;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.PerformanceRecord;
import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.enums.RepEntryStatus;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.PerformanceRecordRepository;
import com.coachsync.repository.SessionBlockRepository;
import com.coachsync.web.dto.PerformanceRequest;
import com.coachsync.web.dto.PerformanceResponse;
import com.coachsync.web.dto.PerformanceUpsertRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
public class PerformanceService {

    private final PerformanceRecordRepository performance;
    private final SessionBlockRepository blocks;
    private final AthleteRepository athletes;

    public PerformanceService(PerformanceRecordRepository performance, SessionBlockRepository blocks,
                              AthleteRepository athletes) {
        this.performance = performance;
        this.blocks = blocks;
        this.athletes = athletes;
    }

    @Transactional(readOnly = true)
    public List<PerformanceResponse> listForBlock(UUID blockId) {
        if (!blocks.existsById(blockId)) {
            throw new NotFoundException("No block with id " + blockId);
        }
        return performance.findBySessionBlockId(blockId).stream()
                .sorted(Comparator.comparingInt(PerformanceRecord::getRepNumber))
                .map(PerformanceResponse::from)
                .toList();
    }

    /**
     * Records a rep result. COMPLETE keeps the supplied time (which is required and
     * must be positive — a 0 ms rep is not a real result); DNS/DNF/PENDING clear it.
     */
    @Transactional
    public PerformanceResponse record(UUID id, PerformanceRequest request) {
        PerformanceRecord slot = performance.findById(id)
                .orElseThrow(() -> new NotFoundException("No performance record with id " + id));
        if (request.status() == RepEntryStatus.COMPLETE
                && (request.recordedTimeMs() == null || request.recordedTimeMs() <= 0)) {
            throw new BadRequestException("A COMPLETE rep result requires a positive recordedTimeMs.");
        }
        if (holdsRecordedData(slot) && SyncTimestamps.isStale(slot, request.updatedAt())) {
            return PerformanceResponse.from(slot);
        }
        slot.setStatus(request.status());
        slot.setRecordedTimeMs(request.status() == RepEntryStatus.COMPLETE ? request.recordedTimeMs() : null);
        slot.setUpdatedAt(SyncTimestamps.resolve(request.updatedAt()));
        return PerformanceResponse.from(performance.save(slot));
    }

    /**
     * Natural-key upsert of rep results for a block — the app↔backend sync path. Slots are matched
     * by (block, athlete, rep) rather than by id, because the iOS app and the backend each generate
     * their own rep-slot ids (the backend via slot reconciliation), so ids never line up. Missing
     * slots are created; each entry is applied last-write-wins (skip-stale).
     */
    @Transactional
    public List<PerformanceResponse> upsertForBlock(UUID blockId, PerformanceUpsertRequest request) {
        SessionBlock block = blocks.findById(blockId)
                .orElseThrow(() -> new NotFoundException("No block with id " + blockId));

        Map<String, PerformanceRecord> bySlot = performance.findBySessionBlockId(blockId).stream()
                .collect(Collectors.toMap(r -> slotKey(r.getAthlete().getId(), r.getRepNumber()),
                        r -> r, (a, b) -> a));
        List<UUID> athleteIds = request.entries().stream()
                .map(PerformanceUpsertRequest.Entry::athleteId).toList();
        Map<UUID, Athlete> athletesById = athletes.findAllById(athleteIds).stream()
                .collect(Collectors.toMap(Athlete::getId, a -> a));

        int capacity = SlotGenerationService.slotCapacity(block);
        Set<PerformanceRecord> touched = new LinkedHashSet<>();
        for (PerformanceUpsertRequest.Entry entry : request.entries()) {
            // A result outside the block's reps would be a filled slot that reconciliation never
            // prunes, stranding it beyond capacity. 400 (not 409) so the app keeps it queued: the
            // block edit that raises capacity may simply not have synced yet.
            if (entry.repNumber() < 1 || entry.repNumber() > capacity) {
                throw new BadRequestException("Rep " + entry.repNumber() + " is outside block " + blockId
                        + ", which has " + capacity + " rep(s).");
            }
            if (entry.status() == RepEntryStatus.COMPLETE
                    && (entry.recordedTimeMs() == null || entry.recordedTimeMs() <= 0)) {
                throw new BadRequestException("A COMPLETE rep result requires a positive recordedTimeMs.");
            }
            Athlete athlete = athletesById.get(entry.athleteId());
            if (athlete == null) {
                throw new NotFoundException("No athlete with id " + entry.athleteId());
            }
            PerformanceRecord slot = bySlot.computeIfAbsent(
                    slotKey(entry.athleteId(), entry.repNumber()), k -> {
                        PerformanceRecord created = new PerformanceRecord();
                        created.setSessionBlock(block);
                        created.setAthlete(athlete);
                        created.setRepNumber(entry.repNumber());
                        return created;
                    });
            // A PENDING placeholder — often pre-created by slot reconciliation with a *server*
            // timestamp — must never block a real client result via last-write-wins. Skip-stale
            // applies only when the stored slot already holds a recorded result.
            if (holdsRecordedData(slot) && SyncTimestamps.isStale(slot, entry.updatedAt())) {
                continue;
            }
            slot.setStatus(entry.status());
            slot.setRecordedTimeMs(entry.status() == RepEntryStatus.COMPLETE ? entry.recordedTimeMs() : null);
            slot.setUpdatedAt(SyncTimestamps.resolve(entry.updatedAt()));
            touched.add(slot);
        }
        performance.saveAll(touched);
        return performance.findBySessionBlockId(blockId).stream()
                .sorted(Comparator.comparingInt(PerformanceRecord::getRepNumber))
                .map(PerformanceResponse::from)
                .toList();
    }

    /** True once a slot holds coach-recorded data — a time, DNS, or DNF (not a PENDING placeholder). */
    private static boolean holdsRecordedData(PerformanceRecord slot) {
        return slot.getRecordedTimeMs() != null || slot.getStatus() != RepEntryStatus.PENDING;
    }

    private static String slotKey(UUID athleteId, int repNumber) {
        return athleteId + "#" + repNumber;
    }
}
