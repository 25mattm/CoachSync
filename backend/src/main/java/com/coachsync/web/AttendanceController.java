package com.coachsync.web;

import com.coachsync.service.AttendanceService;
import com.coachsync.service.ReconcileCoordinator;
import com.coachsync.web.dto.AttendanceResponse;
import com.coachsync.web.dto.AttendanceUpdateRequest;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * Session-scoped attendance. {@code PUT /api/sessions/{sessionId}/attendance}
 * replaces the roster's statuses and then re-runs slot reconciliation via
 * {@link ReconcileCoordinator}, so newly present athletes gain rep slots and
 * newly absent ones shed their unfilled ones.
 */
@RestController
public class AttendanceController {

    private final AttendanceService attendanceService;
    private final ReconcileCoordinator reconcile;

    public AttendanceController(AttendanceService attendanceService, ReconcileCoordinator reconcile) {
        this.attendanceService = attendanceService;
        this.reconcile = reconcile;
    }

    @GetMapping("/api/sessions/{sessionId}/attendance")
    public List<AttendanceResponse> list(@PathVariable UUID sessionId) {
        return attendanceService.list(sessionId);
    }

    /** Replaces the session's attendance, then reconciles rep slots to the new present roster. */
    @PutMapping("/api/sessions/{sessionId}/attendance")
    public List<AttendanceResponse> set(
            @PathVariable UUID sessionId, @Valid @RequestBody AttendanceUpdateRequest request) {
        List<AttendanceResponse> updated = attendanceService.set(sessionId, request);
        reconcile.reconcile(sessionId);
        return updated;
    }
}
