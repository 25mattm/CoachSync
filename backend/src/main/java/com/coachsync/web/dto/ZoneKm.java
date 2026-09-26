package com.coachsync.web.dto;

import com.coachsync.domain.enums.TrainingZone;

/** Km accumulated in one training zone over a season (recovery excluded). */
public record ZoneKm(TrainingZone zone, double km) {
}
