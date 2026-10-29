package com.coachsync.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.Lob;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

import org.hibernate.Length;

import java.time.Instant;

/**
 * A free-text coaching note about an athlete, anchored to a session and
 * optionally a specific block. The {@code coach} reference replaces the app's
 * {@code createdByCoachName} stamp.
 */
@Entity
@Table(name = "athlete_note")
public class AthleteNote extends TenantScoped {

    // length = LONG32 keeps this LONGTEXT on MySQL. A bare @Column defaults to
    // length 255, which combined with @Lob would render as TINYTEXT.
    @Lob
    @Column(nullable = false, length = Length.LONG32)
    private String noteText;

    private Instant createdAt = Timestamps.now();

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "athlete_id", nullable = false)
    private Athlete athlete;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "session_id", nullable = false)
    private CoachSession session;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "session_block_id")
    private SessionBlock sessionBlock;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "coach_id")
    private Coach coach;

    public String getNoteText() {
        return noteText;
    }

    public void setNoteText(String noteText) {
        this.noteText = noteText;
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

    public CoachSession getSession() {
        return session;
    }

    public void setSession(CoachSession session) {
        this.session = session;
    }

    public SessionBlock getSessionBlock() {
        return sessionBlock;
    }

    public void setSessionBlock(SessionBlock sessionBlock) {
        this.sessionBlock = sessionBlock;
    }

    public Coach getCoach() {
        return coach;
    }

    public void setCoach(Coach coach) {
        this.coach = coach;
    }
}
