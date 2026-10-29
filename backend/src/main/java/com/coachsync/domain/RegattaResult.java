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
 * A race result for an athlete, stored alongside training data for trend
 * analysis. {@code resultTimeMs} is milliseconds; {@code eventDistanceMetres}
 * is metres.
 */
@Entity
@Table(name = "regatta_result")
public class RegattaResult extends TenantScoped {

    @Column(nullable = false)
    private String regattaName;

    private String location;

    @Column(nullable = false)
    private LocalDate regattaDate;

    private int eventDistanceMetres;

    private Integer placement;

    private Integer totalCompetitors;

    private int resultTimeMs;

    @Lob
    private String notes;

    private Instant createdAt = Timestamps.now();

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "athlete_id", nullable = false)
    private Athlete athlete;

    public String getRegattaName() {
        return regattaName;
    }

    public void setRegattaName(String regattaName) {
        this.regattaName = regattaName;
    }

    public String getLocation() {
        return location;
    }

    public void setLocation(String location) {
        this.location = location;
    }

    public LocalDate getRegattaDate() {
        return regattaDate;
    }

    public void setRegattaDate(LocalDate regattaDate) {
        this.regattaDate = regattaDate;
    }

    public int getEventDistanceMetres() {
        return eventDistanceMetres;
    }

    public void setEventDistanceMetres(int eventDistanceMetres) {
        this.eventDistanceMetres = eventDistanceMetres;
    }

    public Integer getPlacement() {
        return placement;
    }

    public void setPlacement(Integer placement) {
        this.placement = placement;
    }

    public Integer getTotalCompetitors() {
        return totalCompetitors;
    }

    public void setTotalCompetitors(Integer totalCompetitors) {
        this.totalCompetitors = totalCompetitors;
    }

    public int getResultTimeMs() {
        return resultTimeMs;
    }

    public void setResultTimeMs(int resultTimeMs) {
        this.resultTimeMs = resultTimeMs;
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
