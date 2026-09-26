package com.coachsync.domain;

import com.coachsync.domain.enums.RepEntryStatus;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.Instant;

/**
 * A single per-athlete rep slot on a session block. The backend pre-generates
 * one row per present athlete × rep; {@code repNumber} runs 1..repetitionCount.
 * At most one row per (sessionBlock, athlete, repNumber) — unique constraint.
 *
 * <p>There is deliberately <strong>no</strong> FK to AttendanceRecord: the
 * attendance snapshot is the input to slot generation, but late arrivals /
 * changed minds must not break referential integrity (reconciliation is
 * endpoint logic).
 */
@Entity
@Table(
        name = "performance_record",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_performance_block_athlete_rep",
                columnNames = {"session_block_id", "athlete_id", "rep_number"}))
public class PerformanceRecord extends TenantScoped {

    @Column(name = "rep_number", nullable = false)
    private int repNumber;

    /** Recorded time in milliseconds; null until a result is entered. */
    private Integer recordedTimeMs;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.VARCHAR)
    @Column(nullable = false)
    private RepEntryStatus status = RepEntryStatus.PENDING;

    private Instant createdAt = Instant.now();

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "session_block_id", nullable = false)
    private SessionBlock sessionBlock;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "athlete_id", nullable = false)
    private Athlete athlete;

    public int getRepNumber() {
        return repNumber;
    }

    public void setRepNumber(int repNumber) {
        this.repNumber = repNumber;
    }

    public Integer getRecordedTimeMs() {
        return recordedTimeMs;
    }

    public void setRecordedTimeMs(Integer recordedTimeMs) {
        this.recordedTimeMs = recordedTimeMs;
    }

    public RepEntryStatus getStatus() {
        return status;
    }

    public void setStatus(RepEntryStatus status) {
        this.status = status;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }

    public SessionBlock getSessionBlock() {
        return sessionBlock;
    }

    public void setSessionBlock(SessionBlock sessionBlock) {
        this.sessionBlock = sessionBlock;
    }

    public Athlete getAthlete() {
        return athlete;
    }

    public void setAthlete(Athlete athlete) {
        this.athlete = athlete;
    }
}
