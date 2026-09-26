package com.coachsync;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.AttendanceRecord;
import com.coachsync.domain.Coach;
import com.coachsync.domain.CoachSession;
import com.coachsync.domain.PerformanceRecord;
import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.Team;
import com.coachsync.domain.enums.AttendanceStatus;
import com.coachsync.domain.enums.BlockType;
import com.coachsync.domain.enums.Gender;
import com.coachsync.domain.enums.RepEntryStatus;
import com.coachsync.domain.enums.TrainingZone;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.AttendanceRecordRepository;
import com.coachsync.repository.CoachRepository;
import com.coachsync.repository.CoachSessionRepository;
import com.coachsync.repository.PerformanceRecordRepository;
import com.coachsync.repository.SessionBlockRepository;
import com.coachsync.repository.TeamRepository;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Behavioural proof that the schema actually works through the repositories
 * (against in-memory H2): assigned-UUID PKs populate on save, a full session
 * graph round-trips (ordered element collection + enums included), the
 * attendance unique constraint rejects duplicates, and deleting a session
 * cascades to its children while leaving the athlete intact.
 *
 * <p>Each test runs in a transaction that is rolled back afterwards.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
@Transactional
class TrainingLogPersistenceTest {

    @PersistenceContext private EntityManager em;
    @Autowired private CoachRepository coaches;
    @Autowired private AthleteRepository athletes;
    @Autowired private TeamRepository teams;
    @Autowired private CoachSessionRepository sessions;
    @Autowired private SessionBlockRepository blocks;
    @Autowired private AttendanceRecordRepository attendance;
    @Autowired private PerformanceRecordRepository performance;

    private Athlete newAthlete(String first, String last) {
        Athlete a = new Athlete();
        a.setFirstName(first);
        a.setLastName(last);
        a.setDateOfBirth(LocalDate.of(2014, 5, 1));
        a.setGender(Gender.FEMALE);
        return a;
    }

    private CoachSession newSession(String name, LocalDate date) {
        CoachSession s = new CoachSession();
        s.setSessionName(name);
        s.setScheduledDate(date);
        return s;
    }

    @Test
    void assignsUuidPkAndRoundTripsSessionGraph() {
        Coach coach = new Coach();
        coach.setName("Pat Coach");
        coaches.save(coach);

        Team team = new Team();
        team.setTeamName("U14 Sprint");
        teams.save(team);

        Athlete athlete = athletes.save(newAthlete("Ada", "Paddle"));

        CoachSession session = newSession("Tuesday AM", LocalDate.of(2026, 6, 16));
        session.setCoach(coach);
        session.setTeam(team);
        sessions.save(session);

        SessionBlock block = new SessionBlock();
        block.setBlockName("8x200m");
        block.setBlockType(BlockType.PADDLE_DISTANCE);
        block.setRepetitionCount(8);
        block.setTrainingZone(TrainingZone.AN_MIX);
        block.setSession(session);
        block.getPrescribedRepDurationsSec().add(55);
        block.getPrescribedRepDurationsSec().add(54);
        blocks.save(block);

        PerformanceRecord rep = new PerformanceRecord();
        rep.setRepNumber(1);
        rep.setRecordedTimeMs(54210);
        rep.setStatus(RepEntryStatus.COMPLETE);
        rep.setSessionBlock(block);
        rep.setAthlete(athlete);
        performance.save(rep);

        // Assigned-UUID PK policy: the caller never set an id, yet one is present.
        assertThat(coach.getId()).isNotNull();
        assertThat(session.getId()).isNotNull();
        assertThat(block.getId()).isNotNull();
        assertThat(rep.getId()).isNotNull();

        UUID blockId = block.getId();
        em.flush();
        em.clear();

        // Real DB round-trip: ordered element collection + enums survive intact.
        SessionBlock reloaded = blocks.findById(blockId).orElseThrow();
        assertThat(reloaded.getBlockType()).isEqualTo(BlockType.PADDLE_DISTANCE);
        assertThat(reloaded.getTrainingZone()).isEqualTo(TrainingZone.AN_MIX);
        assertThat(reloaded.getPrescribedRepDurationsSec()).containsExactly(55, 54);

        assertThat(performance.findBySessionBlockIdAndAthleteIdAndRepNumber(
                blockId, athlete.getId(), 1)).isPresent();
    }

    @Test
    void enforcesAttendanceUniqueConstraint() {
        Athlete athlete = athletes.save(newAthlete("Mo", "Sprint"));
        CoachSession session = sessions.save(newSession("Wed PM", LocalDate.of(2026, 6, 17)));

        AttendanceRecord first = new AttendanceRecord();
        first.setSession(session);
        first.setAthlete(athlete);
        first.setStatus(AttendanceStatus.PRESENT);
        attendance.saveAndFlush(first);

        AttendanceRecord duplicate = new AttendanceRecord();
        duplicate.setSession(session);
        duplicate.setAthlete(athlete);
        duplicate.setStatus(AttendanceStatus.ABSENT);

        assertThatThrownBy(() -> attendance.saveAndFlush(duplicate))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void enforcesPerformanceRepUniqueConstraint() {
        Athlete athlete = athletes.save(newAthlete("Uri", "Rep"));
        CoachSession session = sessions.save(newSession("Thu PM", LocalDate.of(2026, 6, 18)));
        SessionBlock block = new SessionBlock();
        block.setBlockName("8x100m");
        block.setBlockType(BlockType.PADDLE_DISTANCE);
        block.setSession(session);
        blocks.save(block);

        PerformanceRecord first = new PerformanceRecord();
        first.setSessionBlock(block);
        first.setAthlete(athlete);
        first.setRepNumber(1);
        performance.saveAndFlush(first);

        PerformanceRecord duplicate = new PerformanceRecord();
        duplicate.setSessionBlock(block);
        duplicate.setAthlete(athlete);
        duplicate.setRepNumber(1);

        assertThatThrownBy(() -> performance.saveAndFlush(duplicate))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void deletingSessionCascadesToChildrenButRetainsAthlete() {
        Athlete athlete = athletes.save(newAthlete("Sam", "Stroke"));
        CoachSession session = sessions.save(newSession("Friday AM", LocalDate.of(2026, 6, 19)));

        SessionBlock block = new SessionBlock();
        block.setBlockName("Core");
        block.setBlockType(BlockType.CORE);
        block.setSession(session);
        blocks.save(block);

        PerformanceRecord rep = new PerformanceRecord();
        rep.setRepNumber(1);
        rep.setSessionBlock(block);
        rep.setAthlete(athlete);
        performance.save(rep);

        AttendanceRecord att = new AttendanceRecord();
        att.setSession(session);
        att.setAthlete(athlete);
        attendance.save(att);

        UUID sessionId = session.getId();
        UUID blockId = block.getId();
        em.flush();
        em.clear();

        sessions.delete(sessions.findById(sessionId).orElseThrow());
        em.flush();

        assertThat(blocks.findById(blockId)).isEmpty();
        assertThat(performance.findBySessionBlockId(blockId)).isEmpty();
        assertThat(attendance.findBySessionId(sessionId)).isEmpty();
        // Only the session's children cascade; the athlete is retained.
        assertThat(athletes.findById(athlete.getId())).isPresent();
    }
}
