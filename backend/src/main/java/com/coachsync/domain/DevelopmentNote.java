package com.coachsync.domain;

import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.Lob;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

import org.hibernate.Length;

import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/**
 * A development-journal entry for an athlete: free text plus optional topic tags.
 * Athlete-scoped and tagged — distinct from the session-anchored
 * {@link AthleteNote}. The optional {@code coach} is the "logged by" author.
 */
@Entity
@Table(name = "development_note")
public class DevelopmentNote extends TenantScoped {

    @Column(nullable = false)
    private LocalDate date;

    // length = LONG32 keeps this LONGTEXT on MySQL — a nullable=false @Lob at the
    // default 255 length would render as TINYTEXT (same fix as AthleteNote).
    @Lob
    @Column(nullable = false, length = Length.LONG32)
    private String text;

    @ElementCollection
    @CollectionTable(
            name = "development_note_tags",
            joinColumns = @JoinColumn(name = "development_note_id"))
    @Column(name = "tag")
    private List<String> tags = new ArrayList<>();

    private Instant createdAt = Instant.now();

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "athlete_id", nullable = false)
    private Athlete athlete;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "coach_id")
    private Coach coach;

    public LocalDate getDate() {
        return date;
    }

    public void setDate(LocalDate date) {
        this.date = date;
    }

    public String getText() {
        return text;
    }

    public void setText(String text) {
        this.text = text;
    }

    public List<String> getTags() {
        return tags;
    }

    public void setTags(List<String> tags) {
        this.tags = tags;
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

    public Coach getCoach() {
        return coach;
    }

    public void setCoach(Coach coach) {
        this.coach = coach;
    }
}
