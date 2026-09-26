package com.coachsync.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

/**
 * One scored factor (1–5) within a {@link TechnicalAssessment}. The 1–5 bound is
 * enforced at the API (validation → 400), not silently clamped.
 */
@Entity
@Table(name = "technical_rating")
public class TechnicalRating extends TenantScoped {

    @Column(nullable = false)
    private String category;

    @Column(nullable = false)
    private String factor;

    @Column(nullable = false)
    private int score = 1;

    private String comment;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "assessment_id", nullable = false)
    private TechnicalAssessment assessment;

    public String getCategory() {
        return category;
    }

    public void setCategory(String category) {
        this.category = category;
    }

    public String getFactor() {
        return factor;
    }

    public void setFactor(String factor) {
        this.factor = factor;
    }

    public int getScore() {
        return score;
    }

    public void setScore(int score) {
        this.score = score;
    }

    public String getComment() {
        return comment;
    }

    public void setComment(String comment) {
        this.comment = comment;
    }

    public TechnicalAssessment getAssessment() {
        return assessment;
    }

    public void setAssessment(TechnicalAssessment assessment) {
        this.assessment = assessment;
    }
}
