package com.coachsync.domain.enums;

/**
 * Per-session per-athlete attendance. Only PRESENT athletes receive generated
 * performance-record slots (slot-generation logic, a later vertical).
 */
public enum AttendanceStatus {
    PRESENT,
    ABSENT,
    EXCUSED
}
