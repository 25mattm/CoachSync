package com.coachsync.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.Lob;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

import java.time.Instant;
import java.time.LocalDate;

/**
 * A CKC Kayak Technical Check (KTC) snapshot for an athlete at a seasonal
 * window: four 1–5 stroke-phase scores (setup/recovery, catch, propulsion/draw,
 * exit). The 1–5 bound is enforced at the API. Named {@code KtcAssessment} (not
 * all-caps) so the naming strategy yields {@code ktc_assessment}.
 */
@Entity
@Table(name = "ktc_assessment")
public class KtcAssessment extends TenantScoped {

    @Column(nullable = false)
    private LocalDate date;

    // "window" is a reserved SQL word (window functions) — map to a safe column.
    @Column(name = "ktc_window", nullable = false)
    private String window;

    @Column(nullable = false)
    private int setupRecoveryScore = 1;

    @Column(nullable = false)
    private int catchScore = 1;

    @Column(nullable = false)
    private int propulsionDrawScore = 1;

    @Column(nullable = false)
    private int exitScore = 1;

    @Lob
    private String notes;

    private Instant createdAt = Timestamps.now();

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "athlete_id", nullable = false)
    private Athlete athlete;

    public LocalDate getDate() {
        return date;
    }

    public void setDate(LocalDate date) {
        this.date = date;
    }

    public String getWindow() {
        return window;
    }

    public void setWindow(String window) {
        this.window = window;
    }

    public int getSetupRecoveryScore() {
        return setupRecoveryScore;
    }

    public void setSetupRecoveryScore(int setupRecoveryScore) {
        this.setupRecoveryScore = setupRecoveryScore;
    }

    public int getCatchScore() {
        return catchScore;
    }

    public void setCatchScore(int catchScore) {
        this.catchScore = catchScore;
    }

    public int getPropulsionDrawScore() {
        return propulsionDrawScore;
    }

    public void setPropulsionDrawScore(int propulsionDrawScore) {
        this.propulsionDrawScore = propulsionDrawScore;
    }

    public int getExitScore() {
        return exitScore;
    }

    public void setExitScore(int exitScore) {
        this.exitScore = exitScore;
    }

    public String getNotes() {
        return notes;
    }

    public void setNotes(String notes) {
        this.notes = notes;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }

    public Athlete getAthlete() {
        return athlete;
    }

    public void setAthlete(Athlete athlete) {
        this.athlete = athlete;
    }
}
