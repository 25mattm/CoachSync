package com.coachsync.web.dto;

/** The worst-offending block for rep-to-rep pacing variability, and its CV %. */
public record InconsistentPacing(String blockName, int cvPercent) {
}
