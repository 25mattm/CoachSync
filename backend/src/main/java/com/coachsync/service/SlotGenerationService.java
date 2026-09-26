package com.coachsync.service;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.AttendanceRecord;
import com.coachsync.domain.CoachSession;
import com.coachsync.domain.PerformanceRecord;
import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.enums.AttendanceStatus;
import com.coachsync.domain.enums.BlockType;
import com.coachsync.domain.enums.RepEntryStatus;
import com.coachsync.repository.AttendanceRecordRepository;
import com.coachsync.repository.CoachSessionRepository;
import com.coachsync.repository.PerformanceRecordRepository;
import com.coachsync.repository.SessionBlockRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * Reconciles per-athlete {@code PerformanceRecord} rep slots for a session
 * against its current attendance + block setup. Ports the iOS logger backfill
 * ({@code SessionLoggerView.backfillSlotsIfNeeded}) and the block-edit save
 * guard ({@code AddBlockSheet.commit}).
 *
 * <p>The two resolved rules: only {@link BlockType#capturesPerRepData()} types
 * get slots, and the per-athlete count is {@code repetitionCount} alone
 * ({@code setCount} never multiplies). Attendance is the input snapshot — there
 * is no FK from PerformanceRecord, so reconciliation (late arrivals / changed
 * minds) is exactly this service's job.
 */
@Service
public class SlotGenerationService {

    private final PerformanceRecordRepository performanceRecords;
    private final AttendanceRecordRepository attendanceRecords;
    private final SessionBlockRepository sessionBlocks;
    private final CoachSessionRepository coachSessions;

    public SlotGenerationService(PerformanceRecordRepository performanceRecords,
                                 AttendanceRecordRepository attendanceRecords,
                                 SessionBlockRepository sessionBlocks,
                                 CoachSessionRepository coachSessions) {
        this.performanceRecords = performanceRecords;
        this.attendanceRecords = attendanceRecords;
        this.sessionBlocks = sessionBlocks;
        this.coachSessions = coachSessions;
    }

    /**
     * Loads the session and reconciles all its blocks — the entry point the write
     * endpoints call (in its own transaction, so a concurrent-reconcile race can
     * be retried by the caller).
     */
    @Transactional
    public int reconcileSession(UUID sessionId) {
        CoachSession session = coachSessions.findById(sessionId)
                .orElseThrow(() -> new NotFoundException("No session with id " + sessionId));
        return reconcile(session);
    }

    /** Reconciles every block in the session. Idempotent; returns slots changed. */
    @Transactional
    public int reconcile(CoachSession session) {
        UUID sessionId = session.getId();

        List<Athlete> present = attendanceRecords.findBySessionId(sessionId).stream()
                .filter(a -> a.getStatus() == AttendanceStatus.PRESENT)
                .map(AttendanceRecord::getAthlete)
                .toList();
        Set<UUID> presentIds = new HashSet<>();
        for (Athlete athlete : present) {
            presentIds.add(athlete.getId());
        }

        int changes = 0;
        for (SessionBlock block : sessionBlocks.findBySessionIdOrderBySortOrderAsc(sessionId)) {
            changes += reconcileBlock(block, present, presentIds);
        }
        return changes;
    }

    /**
     * Rep slots a block holds per present athlete: {@code repetitionCount} (at least 1) for a
     * per-rep-capturing type, 0 for a note-only type. Rep numbers run 1..this.
     */
    static int slotCapacity(SessionBlock block) {
        return block.getBlockType().capturesPerRepData() ? Math.max(block.getRepetitionCount(), 1) : 0;
    }

    private int reconcileBlock(SessionBlock block, List<Athlete> present, Set<UUID> presentIds) {
        boolean captures = block.getBlockType().capturesPerRepData();
        int totalReps = slotCapacity(block);

        List<PerformanceRecord> existing = performanceRecords.findBySessionBlockId(block.getId());

        // Collect prunable slots: UNFILLED ones beyond capacity, or (for capturing
        // blocks) belonging to athletes no longer present. Filled slots are kept.
        List<PerformanceRecord> toDelete = new ArrayList<>();
        for (PerformanceRecord record : existing) {
            if (isFilled(record)) {
                continue;
            }
            UUID athleteId = record.getAthlete() != null ? record.getAthlete().getId() : null;
            boolean beyondCapacity = record.getRepNumber() > totalReps;
            boolean nowAbsent = captures
                    && record.getRepNumber() <= totalReps
                    && athleteId != null
                    && !presentIds.contains(athleteId);
            if (beyondCapacity || nowAbsent) {
                toDelete.add(record);
            }
        }

        // Collect a PENDING slot for each present athlete × rep that is missing.
        List<PerformanceRecord> toInsert = new ArrayList<>();
        if (captures) {
            Set<String> have = new HashSet<>();
            for (PerformanceRecord record : existing) {
                if (record.getAthlete() != null) {
                    have.add(slotKey(record.getAthlete().getId(), record.getRepNumber()));
                }
            }
            for (Athlete athlete : present) {
                for (int rep = 1; rep <= totalReps; rep++) {
                    if (have.add(slotKey(athlete.getId(), rep))) {
                        PerformanceRecord slot = new PerformanceRecord();
                        slot.setSessionBlock(block);
                        slot.setAthlete(athlete);
                        slot.setRepNumber(rep);
                        slot.setStatus(RepEntryStatus.PENDING);
                        toInsert.add(slot);
                    }
                }
            }
        }

        // One batched DELETE and one batched INSERT (hibernate.jdbc.batch_size).
        if (!toDelete.isEmpty()) {
            performanceRecords.deleteAllInBatch(toDelete);
        }
        if (!toInsert.isEmpty()) {
            performanceRecords.saveAll(toInsert);
        }
        return toDelete.size() + toInsert.size();
    }

    /**
     * Guards a proposed block edit — refuses it if it would strand recorded
     * results (shrinking capacity below a filled rep, or switching to a type that
     * captures no per-rep data while filled slots exist).
     */
    @Transactional(readOnly = true)
    public void assertEditAllowed(SessionBlock block, BlockType newType, int newRepetitionCount) {
        int newCapacity = newType.capturesPerRepData() ? Math.max(newRepetitionCount, 1) : 0;
        int highestFilled = highestFilledRepNumber(block.getId());
        if (highestFilled > newCapacity) {
            throw new StrandedResultsException(block.getId(), highestFilled, newCapacity);
        }
    }

    /** Guards a block delete — refuses it if the block holds any recorded result. */
    @Transactional(readOnly = true)
    public void assertDeletable(SessionBlock block) {
        int highestFilled = highestFilledRepNumber(block.getId());
        if (highestFilled > 0) {
            throw new StrandedResultsException(block.getId(), highestFilled, 0);
        }
    }

    private int highestFilledRepNumber(UUID blockId) {
        return performanceRecords.findBySessionBlockId(blockId).stream()
                .filter(SlotGenerationService::isFilled)
                .mapToInt(PerformanceRecord::getRepNumber)
                .max()
                .orElse(0);
    }

    /** A slot is "filled" once it holds a result: a recorded time, DNS, or DNF. */
    private static boolean isFilled(PerformanceRecord record) {
        return record.getRecordedTimeMs() != null || record.getStatus() != RepEntryStatus.PENDING;
    }

    private static String slotKey(UUID athleteId, int repNumber) {
        return athleteId + "#" + repNumber;
    }
}
