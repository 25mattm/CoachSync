package com.coachsync.domain;

import com.coachsync.domain.enums.DevelopmentStage;
import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.Lob;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;

import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/**
 * A technical assessment for an athlete on a date: a development-stage snapshot
 * plus a set of 1–5 factor ratings. Ratings are a strict single-owner aggregate
 * of the assessment (orphanRemoval prunes ratings dropped on edit — like
 * session→blocks).
 */
@Entity
@Table(name = "technical_assessment")
public class TechnicalAssessment extends TenantScoped {

    @Column(nullable = false)
    private LocalDate date;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.VARCHAR)
    @Column(nullable = false)
    private DevelopmentStage stage = DevelopmentStage.INITIATION;

    @Lob
    private String overallNotes;

    private Instant createdAt = Instant.now();

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "athlete_id", nullable = false)
    private Athlete athlete;

    @OneToMany(mappedBy = "assessment", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<TechnicalRating> ratings = new ArrayList<>();

    public LocalDate getDate() {
        return date;
    }

    public void setDate(LocalDate date) {
        this.date = date;
    }

    public DevelopmentStage getStage() {
        return stage;
    }

    public void setStage(DevelopmentStage stage) {
        this.stage = stage;
    }

    public String getOverallNotes() {
        return overallNotes;
    }

    public void setOverallNotes(String overallNotes) {
        this.overallNotes = overallNotes;
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

    public List<TechnicalRating> getRatings() {
        return ratings;
    }
}
