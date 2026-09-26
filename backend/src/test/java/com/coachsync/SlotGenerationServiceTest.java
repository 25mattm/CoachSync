package com.coachsync;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.AttendanceRecord;
import com.coachsync.domain.CoachSession;
import com.coachsync.domain.PerformanceRecord;
import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.enums.AttendanceStatus;
import com.coachsync.domain.enums.BlockType;
import com.coachsync.domain.enums.RepEntryStatus;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.AttendanceRecordRepository;
import com.coachsync.repository.CoachSessionRepository;
import com.coachsync.repository.PerformanceRecordRepository;
import com.coachsync.repository.SessionBlockRepository;
import com.coachsync.service.SlotGenerationService;
import com.coachsync.service.StrandedResultsException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Verifies the two resolved slot-generation rules and the full reconcile/guard
 * behaviour against in-memory H2. Mirrors the iOS {@code SlotReconciliationTests}.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
@Transactional
class SlotGenerationServiceTest {

    @Autowired private SlotGenerationService service;
    @Autowired private AthleteRepository athletes;
    @Autowired private CoachSessionRepository sessions;
    @Autowired private SessionBlockRepository blocks;
    @Autowired private AttendanceRecordRepository attendance;
    @Autowired private PerformanceRecordRepository performance;

    // --- Rule 2: which block types capture per-rep data -----------------------

    @Test
    void capturesPerRepDataTruthTable() {
        assertThat(BlockType.PADDLE_DISTANCE.capturesPerRepData()).isTrue();
        assertThat(BlockType.PADDLE_TIME_PIECES.capturesPerRepData()).isTrue();
        assertThat(BlockType.PADDLE_PYRAMID.capturesPerRepData()).isTrue();
        assertThat(BlockType.RUN_DISTANCE.capturesPerRepData()).isTrue();
        assertThat(BlockType.RUN_INTERVALS.capturesPerRepData()).isTrue();
        assertThat(BlockType.WEIGHTS.capturesPerRepData()).isFalse();
        assertThat(BlockType.CIRCUIT.capturesPerRepData()).isFalse();
        assertThat(BlockType.CORE.capturesPerRepData()).isFalse();
        assertThat(BlockType.TECHNIQUE.capturesPerRepData()).isFalse();
    }

    @Test
    void nonCapturingBlockTypeGetsNoSlots() {
        CoachSession session = persistSession();
        SessionBlock core = persistBlock(session, BlockType.CORE, 5, 1);
        markPresent(session, persistAthlete("A", "One"));
        markPresent(session, persistAthlete("B", "Two"));

        int changes = service.reconcile(session);

        assertThat(changes).isZero();
        assertThat(performance.findBySessionBlockId(core.getId())).isEmpty();
    }

    // --- Generation -----------------------------------------------------------

    @Test
    void generatesSlotsForPresentAthletesOnly() {
        CoachSession session = persistSession();
        SessionBlock block = persistBlock(session, BlockType.PADDLE_DISTANCE, 3, 1);
        Athlete present1 = persistAthlete("Ada", "Paddle");
        Athlete present2 = persistAthlete("Mo", "Sprint");
        Athlete absent = persistAthlete("Sam", "Away");
        markPresent(session, present1);
        markPresent(session, present2);
        markAttendance(session, absent, AttendanceStatus.ABSENT);

        service.reconcile(session);

        assertThat(performance.findBySessionBlockId(block.getId())).hasSize(6);
        assertThat(slotsFor(block, present1)).hasSize(3);
        assertThat(slotsFor(block, present2)).hasSize(3);
        assertThat(slotsFor(block, absent)).isEmpty();
    }

    @Test
    void setCountDoesNotMultiplySlotCount() {
        CoachSession session = persistSession();
        // Pyramid: the client already baked sets into repetitionCount
        // (pattern 2 x sets 3 = 6). setCount is descriptive only.
        SessionBlock pyramid = persistBlock(session, BlockType.PADDLE_PYRAMID, 6, 3);
        Athlete athlete = persistAthlete("Pat", "Pyramid");
        markPresent(session, athlete);

        service.reconcile(session);

        // 6, not 6 x 3 = 18.
        assertThat(performance.findBySessionBlockId(pyramid.getId())).hasSize(6);
    }

    @Test
    void backfillInsertsMissingSlots() {
        CoachSession session = persistSession();
        SessionBlock block = persistBlock(session, BlockType.RUN_INTERVALS, 4, 1);
        Athlete athlete = persistAthlete("Lee", "Run");
        markPresent(session, athlete);
        // Only rep 1 exists up front; reconcile should heal reps 2..4.
        persistSlot(block, athlete, 1, RepEntryStatus.PENDING, null);

        int changes = service.reconcile(session);

        assertThat(changes).isEqualTo(3);
        assertThat(slotsFor(block, athlete)).hasSize(4);
    }

    // --- Pruning --------------------------------------------------------------

    @Test
    void prunesUnfilledSlotsBeyondCapacity() {
        CoachSession session = persistSession();
        SessionBlock block = persistBlock(session, BlockType.PADDLE_DISTANCE, 2, 1);
        Athlete athlete = persistAthlete("Kai", "Cap");
        markPresent(session, athlete);
        persistSlot(block, athlete, 1, RepEntryStatus.PENDING, null);
        persistSlot(block, athlete, 2, RepEntryStatus.PENDING, null);
        persistSlot(block, athlete, 3, RepEntryStatus.PENDING, null); // stranded, unfilled

        service.reconcile(session);

        assertThat(slotsFor(block, athlete)).extracting(PerformanceRecord::getRepNumber)
                .containsExactlyInAnyOrder(1, 2);
    }

    @Test
    void prunesUnfilledSlotsForNowAbsentAthlete() {
        CoachSession session = persistSession();
        SessionBlock block = persistBlock(session, BlockType.PADDLE_DISTANCE, 2, 1);
        Athlete athlete = persistAthlete("Eve", "Gone");
        AttendanceRecord record = markPresent(session, athlete);
        persistSlot(block, athlete, 1, RepEntryStatus.PENDING, null);
        persistSlot(block, athlete, 2, RepEntryStatus.PENDING, null);

        // Athlete flips to absent before any result is recorded.
        record.setStatus(AttendanceStatus.ABSENT);
        attendance.save(record);

        service.reconcile(session);

        assertThat(slotsFor(block, athlete)).isEmpty();
    }

    @Test
    void keepsFilledSlotsEvenWhenStrandedOrAbsent() {
        CoachSession session = persistSession();
        SessionBlock block = persistBlock(session, BlockType.PADDLE_DISTANCE, 1, 1);
        Athlete athlete = persistAthlete("Ola", "Filled");
        AttendanceRecord record = markPresent(session, athlete);
        // A recorded time at rep 2 (beyond the capacity of 1) must never be pruned.
        persistSlot(block, athlete, 2, RepEntryStatus.COMPLETE, 54210);
        // A DNF for a now-absent athlete must also survive.
        record.setStatus(AttendanceStatus.ABSENT);
        attendance.save(record);
        persistSlot(block, athlete, 1, RepEntryStatus.DNF, null);

        service.reconcile(session);

        assertThat(slotsFor(block, athlete)).extracting(PerformanceRecord::getRepNumber)
                .containsExactlyInAnyOrder(1, 2);
    }

    // --- Edit guard -----------------------------------------------------------

    @Test
    void assertEditAllowedRefusesStrandingButAllowsSafeEdits() {
        CoachSession session = persistSession();
        SessionBlock block = persistBlock(session, BlockType.PADDLE_DISTANCE, 3, 1);
        Athlete athlete = persistAthlete("Ravi", "Edit");
        markPresent(session, athlete);
        persistSlot(block, athlete, 3, RepEntryStatus.COMPLETE, 60000); // filled at rep 3

        // Shrinking below the filled rep, or going note-only, is refused.
        assertThatThrownBy(() -> service.assertEditAllowed(block, BlockType.PADDLE_DISTANCE, 2))
                .isInstanceOf(StrandedResultsException.class);
        assertThatThrownBy(() -> service.assertEditAllowed(block, BlockType.CORE, 3))
                .isInstanceOf(StrandedResultsException.class);

        // Keeping capacity at or above the highest filled rep is fine.
        assertThatCode(() -> service.assertEditAllowed(block, BlockType.PADDLE_DISTANCE, 3))
                .doesNotThrowAnyException();
        assertThatCode(() -> service.assertEditAllowed(block, BlockType.RUN_INTERVALS, 5))
                .doesNotThrowAnyException();
    }

    // --- Idempotency ----------------------------------------------------------

    @Test
    void reconcileIsIdempotent() {
        CoachSession session = persistSession();
        SessionBlock block = persistBlock(session, BlockType.PADDLE_TIME_PIECES, 2, 1);
        markPresent(session, persistAthlete("Ivy", "Idem"));

        int first = service.reconcile(session);
        int second = service.reconcile(session);

        assertThat(first).isEqualTo(2);
        assertThat(second).isZero();
        assertThat(performance.findBySessionBlockId(block.getId())).hasSize(2);
    }

    // --- Helpers --------------------------------------------------------------

    private List<PerformanceRecord> slotsFor(SessionBlock block, Athlete athlete) {
        return performance.findBySessionBlockId(block.getId()).stream()
                .filter(r -> r.getAthlete() != null && r.getAthlete().getId().equals(athlete.getId()))
                .toList();
    }

    private Athlete persistAthlete(String first, String last) {
        Athlete a = new Athlete();
        a.setFirstName(first);
        a.setLastName(last);
        a.setDateOfBirth(LocalDate.of(2014, 1, 1));
        return athletes.save(a);
    }

    private CoachSession persistSession() {
        CoachSession s = new CoachSession();
        s.setSessionName("Test Session");
        s.setScheduledDate(LocalDate.of(2026, 6, 16));
        return sessions.save(s);
    }

    private SessionBlock persistBlock(CoachSession session, BlockType type, int repetitionCount, int setCount) {
        SessionBlock b = new SessionBlock();
        b.setBlockName(type.name());
        b.setBlockType(type);
        b.setRepetitionCount(repetitionCount);
        b.setSetCount(setCount);
        b.setSession(session);
        return blocks.save(b);
    }

    private AttendanceRecord markPresent(CoachSession session, Athlete athlete) {
        return markAttendance(session, athlete, AttendanceStatus.PRESENT);
    }

    private AttendanceRecord markAttendance(CoachSession session, Athlete athlete, AttendanceStatus status) {
        AttendanceRecord record = new AttendanceRecord();
        record.setSession(session);
        record.setAthlete(athlete);
        record.setStatus(status);
        return attendance.save(record);
    }

    private PerformanceRecord persistSlot(SessionBlock block, Athlete athlete, int rep,
                                          RepEntryStatus status, Integer timeMs) {
        PerformanceRecord slot = new PerformanceRecord();
        slot.setSessionBlock(block);
        slot.setAthlete(athlete);
        slot.setRepNumber(rep);
        slot.setStatus(status);
        slot.setRecordedTimeMs(timeMs);
        return performance.save(slot);
    }
}
