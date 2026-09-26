package com.coachsync.domain;

import com.coachsync.domain.enums.DevelopmentStage;
import com.coachsync.domain.enums.Gender;
import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;

import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/**
 * Shared athlete core — also used by later verticals (competition, assessments).
 * {@code dateOfBirth} is the source of truth for age; {@code ageCategory} is
 * <em>not</em> stored (derived from DOB against the current calendar year).
 */
@Entity
@Table(name = "athlete")
public class Athlete extends TenantScoped {

    @Column(nullable = false)
    private String firstName;

    @Column(nullable = false)
    private String lastName;

    @Column(nullable = false)
    private LocalDate dateOfBirth;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.VARCHAR)
    private Gender gender;

    private String guardianName;

    private String guardianPhone;

    private String guardianEmail;

    private boolean isActive = true;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.VARCHAR)
    @Column(nullable = false)
    private DevelopmentStage developmentStage = DevelopmentStage.INITIATION;

    private Instant createdAt = Instant.now();

    // --- Children: deleting an athlete cascades all recorded history ----------
    @OneToMany(mappedBy = "athlete", cascade = CascadeType.ALL)
    private List<TeamMembership> memberships = new ArrayList<>();

    @OneToMany(mappedBy = "athlete", cascade = CascadeType.ALL)
    private List<AttendanceRecord> attendanceRecords = new ArrayList<>();

    @OneToMany(mappedBy = "athlete", cascade = CascadeType.ALL)
    private List<PerformanceRecord> performanceRecords = new ArrayList<>();

    @OneToMany(mappedBy = "athlete", cascade = CascadeType.ALL)
    private List<AthleteNote> athleteNotes = new ArrayList<>();

    public String getFirstName() {
        return firstName;
    }

    public void setFirstName(String firstName) {
        this.firstName = firstName;
    }

    public String getLastName() {
        return lastName;
    }

    public void setLastName(String lastName) {
        this.lastName = lastName;
    }

    public LocalDate getDateOfBirth() {
        return dateOfBirth;
    }

    public void setDateOfBirth(LocalDate dateOfBirth) {
        this.dateOfBirth = dateOfBirth;
    }

    public Gender getGender() {
        return gender;
    }

    public void setGender(Gender gender) {
        this.gender = gender;
    }

    public String getGuardianName() {
        return guardianName;
    }

    public void setGuardianName(String guardianName) {
        this.guardianName = guardianName;
    }

    public String getGuardianPhone() {
        return guardianPhone;
    }

    public void setGuardianPhone(String guardianPhone) {
        this.guardianPhone = guardianPhone;
    }

    public String getGuardianEmail() {
        return guardianEmail;
    }

    public void setGuardianEmail(String guardianEmail) {
        this.guardianEmail = guardianEmail;
    }

    public boolean isActive() {
        return isActive;
    }

    public void setActive(boolean active) {
        isActive = active;
    }

    public DevelopmentStage getDevelopmentStage() {
        return developmentStage;
    }

    public void setDevelopmentStage(DevelopmentStage developmentStage) {
        this.developmentStage = developmentStage;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }

    public List<TeamMembership> getMemberships() {
        return memberships;
    }

    public List<AttendanceRecord> getAttendanceRecords() {
        return attendanceRecords;
    }

    public List<PerformanceRecord> getPerformanceRecords() {
        return performanceRecords;
    }

    public List<AthleteNote> getAthleteNotes() {
        return athleteNotes;
    }
}
