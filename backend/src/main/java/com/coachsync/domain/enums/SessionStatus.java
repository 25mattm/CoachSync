package com.coachsync.domain.enums;

/**
 * Lifecycle of a {@code CoachSession}: Open until the coach marks it Completed
 * or Cancelled. Stored as the constant name via {@code EnumType.STRING}.
 */
public enum SessionStatus {
    OPEN,
    COMPLETED,
    CANCELLED
}
