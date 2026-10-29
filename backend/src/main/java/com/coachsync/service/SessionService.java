package com.coachsync.service;

import com.coachsync.domain.Coach;
import com.coachsync.domain.CoachSession;
import com.coachsync.domain.Timestamps;
import com.coachsync.domain.enums.SessionStatus;
import com.coachsync.repository.CoachRepository;
import com.coachsync.repository.CoachSessionRepository;
import com.coachsync.repository.TeamRepository;
import com.coachsync.web.dto.SessionRequest;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.UUID;

@Service
public class SessionService {

    private final CoachSessionRepository sessions;
    private final CoachRepository coaches;
    private final TeamRepository teams;

    public SessionService(CoachSessionRepository sessions,
                          CoachRepository coaches,
                          TeamRepository teams) {
        this.sessions = sessions;
        this.coaches = coaches;
        this.teams = teams;
    }

    @Transactional(readOnly = true)
    public Page<CoachSession> list(SessionStatus status, UUID teamId, LocalDate date,
                                   Boolean archived, Pageable pageable) {
        return sessions.search(status, teamId, date, archived, pageable);
    }

    @Transactional(readOnly = true)
    public CoachSession get(UUID id) {
        return sessions.findById(id)
                .orElseThrow(() -> new NotFoundException("No session with id " + id));
    }

    @Transactional
    public CoachSession create(SessionRequest request, UUID creatorCoachId) {
        if (request.id() != null) {
            var existing = sessions.findById(request.id());
            if (existing.isPresent()) {
                CoachSession managed = existing.get();
                if (SyncTimestamps.isStale(managed, request.updatedAt())) {
                    return managed;  // re-sent insert is older than the stored row — last-write-wins
                }
                // Update the stored row in place and PRESERVE the original "logged by" coach — a fresh
                // new+save() would merge over it, resetting createdAt and re-stamping attribution to the
                // re-poster.
                apply(request, managed);
                return sessions.save(managed);
            }
        }
        CoachSession session = new CoachSession();
        if (request.id() != null) {
            session.setId(request.id());
        }
        apply(request, session);
        session.setCoach(resolveCoach(creatorCoachId));
        return sessions.save(session);
    }

    @Transactional
    public CoachSession update(UUID id, SessionRequest request) {
        CoachSession session = get(id);
        if (SyncTimestamps.isStale(session, request.updatedAt())) {
            return session;
        }
        apply(request, session);  // attribution (coach) is set at create and preserved here
        return sessions.save(session);
    }

    @Transactional
    public CoachSession setStatus(UUID id, SessionStatus status) {
        CoachSession session = get(id);
        if (session.getStatus() == SessionStatus.COMPLETED && status != SessionStatus.COMPLETED) {
            throw new ConflictException(
                    "Session " + id + " is completed and cannot be reopened; archive it instead.");
        }
        session.setStatus(status);
        session.setUpdatedAt(Timestamps.now());
        return sessions.save(session);
    }

    @Transactional
    public CoachSession setArchived(UUID id, boolean archived) {
        CoachSession session = get(id);
        session.setArchived(archived);
        session.setUpdatedAt(Timestamps.now());
        return sessions.save(session);
    }

    /**
     * Deletes a session (cascading its blocks, attendance, notes, and rep slots).
     * Completed sessions are protected — archive them instead.
     */
    @Transactional
    public void delete(UUID id) {
        CoachSession session = get(id);
        if (session.getStatus() == SessionStatus.COMPLETED) {
            throw new ConflictException(
                    "Session " + id + " is completed and cannot be deleted; archive it instead.");
        }
        sessions.delete(session);
    }

    private void apply(SessionRequest request, CoachSession session) {
        session.setSessionName(request.sessionName());
        session.setScheduledDate(request.scheduledDate());
        session.setStartTime(request.startTime());
        session.setEndTime(request.endTime());
        session.setWeatherNote(request.weatherNote());
        session.setTeamNote(request.teamNote());
        session.setSessionNote(request.sessionNote());
        session.setMfCue(request.mfCue());
        session.setTeam(request.teamId() == null ? null : teams.findById(request.teamId())
                .orElseThrow(() -> new NotFoundException("No team with id " + request.teamId())));
        // COMPLETED is terminal (the app never reopens one). Letting an edit move it back to OPEN
        // would make the completed-session delete guard a two-request bypass: PUT status, then DELETE.
        // The rest of the edit still applies, so a stale device's field changes aren't lost.
        if (request.status() != null && session.getStatus() != SessionStatus.COMPLETED) {
            session.setStatus(request.status());
        }
        if (request.archived() != null) session.setArchived(request.archived());
        session.setUpdatedAt(SyncTimestamps.resolve(request.updatedAt()));
    }

    /** Resolves the authenticated coach who is the session's creator/"logged by". */
    private Coach resolveCoach(UUID coachId) {
        return coaches.findById(coachId)
                .orElseThrow(() -> new NotFoundException("No coach with id " + coachId));
    }
}
