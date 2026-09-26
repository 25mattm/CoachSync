package com.coachsync.service;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.AttendanceRecord;
import com.coachsync.domain.CoachSession;
import com.coachsync.domain.enums.AttendanceStatus;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.AttendanceRecordRepository;
import com.coachsync.repository.CoachSessionRepository;
import com.coachsync.web.dto.AttendanceEntry;
import com.coachsync.web.dto.AttendanceResponse;
import com.coachsync.web.dto.AttendanceUpdateRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
public class AttendanceService {

    private final AttendanceRecordRepository attendance;
    private final CoachSessionRepository sessions;
    private final AthleteRepository athletes;

    public AttendanceService(AttendanceRecordRepository attendance,
                             CoachSessionRepository sessions,
                             AthleteRepository athletes) {
        this.attendance = attendance;
        this.sessions = sessions;
        this.athletes = athletes;
    }

    @Transactional(readOnly = true)
    public List<AttendanceResponse> list(UUID sessionId) {
        if (!sessions.existsById(sessionId)) {
            throw new NotFoundException("No session with id " + sessionId);
        }
        return attendance.findBySessionId(sessionId).stream().map(AttendanceResponse::from).toList();
    }

    /**
     * Upserts the supplied attendance rows for the session (others are left
     * unchanged). The caller reconciles slots afterwards. PRESENT clears any
     * absence reason.
     */
    @Transactional
    public List<AttendanceResponse> set(UUID sessionId, AttendanceUpdateRequest request) {
        CoachSession session = sessions.findById(sessionId)
                .orElseThrow(() -> new NotFoundException("No session with id " + sessionId));

        // Batch-load the entries' athletes and the session's existing rows up front
        // (one query each) so the upsert loop issues no per-entry queries.
        List<UUID> athleteIds = request.entries().stream().map(AttendanceEntry::athleteId).toList();
        Map<UUID, Athlete> athletesById = athletes.findAllById(athleteIds).stream()
                .collect(Collectors.toMap(Athlete::getId, a -> a));
        Map<UUID, AttendanceRecord> bySessionAthlete = attendance.findBySessionId(sessionId).stream()
                .collect(Collectors.toMap(r -> r.getAthlete().getId(), r -> r));

        Set<AttendanceRecord> touched = new LinkedHashSet<>();
        for (AttendanceEntry entry : request.entries()) {
            Athlete athlete = athletesById.get(entry.athleteId());
            if (athlete == null) {
                throw new NotFoundException("No athlete with id " + entry.athleteId());
            }
            AttendanceRecord record = bySessionAthlete.computeIfAbsent(entry.athleteId(), k -> {
                AttendanceRecord created = new AttendanceRecord();
                created.setSession(session);
                created.setAthlete(athlete);
                return created;
            });
            if (SyncTimestamps.isStale(record, entry.updatedAt())) {
                continue;  // LWW: a newer attendance value is already stored
            }
            record.setStatus(entry.status());
            record.setAbsenceReason(entry.status() == AttendanceStatus.PRESENT ? null : entry.absenceReason());
            record.setUpdatedAt(SyncTimestamps.resolve(entry.updatedAt()));
            touched.add(record);
        }
        attendance.saveAll(touched);
        return attendance.findBySessionId(sessionId).stream().map(AttendanceResponse::from).toList();
    }
}
