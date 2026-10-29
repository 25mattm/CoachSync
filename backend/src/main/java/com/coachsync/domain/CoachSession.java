package com.coachsync.domain;

import com.coachsync.domain.enums.SessionStatus;
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
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * A coaching session (practice). Open until marked Completed/Cancelled.
 * The app's single {@code Date} fields are split here into a calendar
 * {@code scheduledDate} plus clock {@code startTime}/{@code endTime}.
 */
@Entity
@Table(name = "coach_session")
public class CoachSession extends TenantScoped {

    @Column(nullable = false)
    private String sessionName;

    @Column(nullable = false)
    private LocalDate scheduledDate;

    private LocalDateTime startTime;

    private LocalDateTime endTime;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.VARCHAR)
    @Column(nullable = false)
    private SessionStatus status = SessionStatus.OPEN;

    private String weatherNote;

    private String teamNote;

    @Lob
    private String sessionNote;

    private String mfCue;

    private boolean isArchived = false;

    private Instant createdAt = Timestamps.now();

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "coach_id")
    private Coach coach;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "team_id")
    private Team team;

    // --- Children: deleting a session cascades blocks, attendance, notes ------
    // (performance records cascade transitively via SessionBlock). Blocks are a
    // strict single-owner aggregate, so orphanRemoval prunes blocks dropped from
    // the session.
    @OneToMany(mappedBy = "session", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<SessionBlock> sessionBlocks = new ArrayList<>();

    @OneToMany(mappedBy = "session", cascade = CascadeType.ALL)
    private List<AttendanceRecord> attendanceRecords = new ArrayList<>();

    @OneToMany(mappedBy = "session", cascade = CascadeType.ALL)
    private List<AthleteNote> athleteNotes = new ArrayList<>();

    public String getSessionName() {
        return sessionName;
    }

    public void setSessionName(String sessionName) {
        this.sessionName = sessionName;
    }

    public LocalDate getScheduledDate() {
        return scheduledDate;
    }

    public void setScheduledDate(LocalDate scheduledDate) {
        this.scheduledDate = scheduledDate;
    }

    public LocalDateTime getStartTime() {
        return startTime;
    }

    public void setStartTime(LocalDateTime startTime) {
        this.startTime = startTime;
    }

    public LocalDateTime getEndTime() {
        return endTime;
    }

    public void setEndTime(LocalDateTime endTime) {
        this.endTime = endTime;
    }

    public SessionStatus getStatus() {
        return status;
    }

    public void setStatus(SessionStatus status) {
        this.status = status;
    }

    public String getWeatherNote() {
        return weatherNote;
    }

    public void setWeatherNote(String weatherNote) {
        this.weatherNote = weatherNote;
    }

    public String getTeamNote() {
        return teamNote;
    }

    public void setTeamNote(String teamNote) {
        this.teamNote = teamNote;
    }

    public String getSessionNote() {
        return sessionNote;
    }

    public void setSessionNote(String sessionNote) {
        this.sessionNote = sessionNote;
    }

    public String getMfCue() {
        return mfCue;
    }

    public void setMfCue(String mfCue) {
        this.mfCue = mfCue;
    }

    public boolean isArchived() {
        return isArchived;
    }

    public void setArchived(boolean archived) {
        isArchived = archived;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }

    public Coach getCoach() {
        return coach;
    }

    public void setCoach(Coach coach) {
        this.coach = coach;
    }

    public Team getTeam() {
        return team;
    }

    public void setTeam(Team team) {
        this.team = team;
    }

    public List<SessionBlock> getSessionBlocks() {
        return sessionBlocks;
    }

    public List<AttendanceRecord> getAttendanceRecords() {
        return attendanceRecords;
    }

    public List<AthleteNote> getAthleteNotes() {
        return athleteNotes;
    }
}
