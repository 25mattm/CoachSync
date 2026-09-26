package com.coachsync.domain;

import com.coachsync.domain.enums.BlockType;
import com.coachsync.domain.enums.TrainingZone;
import jakarta.persistence.CascadeType;
import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderColumn;
import jakarta.persistence.Table;

import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.util.ArrayList;
import java.util.List;

/**
 * One block within a session (e.g. a paddle distance piece, a circuit). The
 * distance fields ({@code targetDistanceMetres}, {@code distanceKm}) overlap;
 * ported as-is to stay aligned with the app. {@code repetitionCount} is the
 * canonical per-athlete slot capacity.
 */
@Entity
@Table(name = "session_block")
public class SessionBlock extends TenantScoped {

    @Column(nullable = false)
    private String blockName;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.VARCHAR)
    @Column(nullable = false)
    private BlockType blockType = BlockType.PADDLE_DISTANCE;

    private int sortOrder = 0;

    /** Governs the per-athlete performance-record slot count. */
    private int repetitionCount = 1;

    /** Descriptive (see the spec's open items on slot generation). */
    private int setCount = 1;

    private Double targetDistanceMetres;

    private Double distanceKm;

    private Integer restIntervalSeconds;

    private Integer durationSeconds;

    private boolean requiresTimeEntry = true;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.VARCHAR)
    private TrainingZone trainingZone;

    private String drillName;

    private String coachNote;

    /** Ordered, may be empty. Prescribed per-rep target durations, in seconds. */
    @ElementCollection
    @CollectionTable(
            name = "session_block_prescribed_rep_durations",
            joinColumns = @JoinColumn(name = "session_block_id"))
    @OrderColumn(name = "rep_index")
    @Column(name = "duration_sec")
    private List<Integer> prescribedRepDurationsSec = new ArrayList<>();

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "session_id", nullable = false)
    private CoachSession session;

    // --- Children -------------------------------------------------------------
    // Rep slots are a strict single-owner aggregate of the block: orphanRemoval
    // prunes slots dropped when a block's capacity shrinks (block-edit logic).
    @OneToMany(mappedBy = "sessionBlock", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<PerformanceRecord> performanceRecords = new ArrayList<>();

    // A note's block reference is an OPTIONAL anchor (session_block_id is nullable);
    // the note is owned by its athlete + session, not the block. So NO cascade here —
    // deleting a block must NOT delete recorded coaching notes. BlockService.delete
    // nullifies the anchor instead (mirrors the Team -> sessions delete-nullify).
    @OneToMany(mappedBy = "sessionBlock")
    private List<AthleteNote> athleteNotes = new ArrayList<>();

    public String getBlockName() {
        return blockName;
    }

    public void setBlockName(String blockName) {
        this.blockName = blockName;
    }

    public BlockType getBlockType() {
        return blockType;
    }

    public void setBlockType(BlockType blockType) {
        this.blockType = blockType;
    }

    public int getSortOrder() {
        return sortOrder;
    }

    public void setSortOrder(int sortOrder) {
        this.sortOrder = sortOrder;
    }

    public int getRepetitionCount() {
        return repetitionCount;
    }

    public void setRepetitionCount(int repetitionCount) {
        this.repetitionCount = repetitionCount;
    }

    public int getSetCount() {
        return setCount;
    }

    public void setSetCount(int setCount) {
        this.setCount = setCount;
    }

    public Double getTargetDistanceMetres() {
        return targetDistanceMetres;
    }

    public void setTargetDistanceMetres(Double targetDistanceMetres) {
        this.targetDistanceMetres = targetDistanceMetres;
    }

    public Double getDistanceKm() {
        return distanceKm;
    }

    public void setDistanceKm(Double distanceKm) {
        this.distanceKm = distanceKm;
    }

    public Integer getRestIntervalSeconds() {
        return restIntervalSeconds;
    }

    public void setRestIntervalSeconds(Integer restIntervalSeconds) {
        this.restIntervalSeconds = restIntervalSeconds;
    }

    public Integer getDurationSeconds() {
        return durationSeconds;
    }

    public void setDurationSeconds(Integer durationSeconds) {
        this.durationSeconds = durationSeconds;
    }

    public boolean isRequiresTimeEntry() {
        return requiresTimeEntry;
    }

    public void setRequiresTimeEntry(boolean requiresTimeEntry) {
        this.requiresTimeEntry = requiresTimeEntry;
    }

    public TrainingZone getTrainingZone() {
        return trainingZone;
    }

    public void setTrainingZone(TrainingZone trainingZone) {
        this.trainingZone = trainingZone;
    }

    public String getDrillName() {
        return drillName;
    }

    public void setDrillName(String drillName) {
        this.drillName = drillName;
    }

    public String getCoachNote() {
        return coachNote;
    }

    public void setCoachNote(String coachNote) {
        this.coachNote = coachNote;
    }

    public List<Integer> getPrescribedRepDurationsSec() {
        return prescribedRepDurationsSec;
    }

    public void setPrescribedRepDurationsSec(List<Integer> prescribedRepDurationsSec) {
        this.prescribedRepDurationsSec = prescribedRepDurationsSec;
    }

    public CoachSession getSession() {
        return session;
    }

    public void setSession(CoachSession session) {
        this.session = session;
    }

    public List<PerformanceRecord> getPerformanceRecords() {
        return performanceRecords;
    }

    public List<AthleteNote> getAthleteNotes() {
        return athleteNotes;
    }
}
