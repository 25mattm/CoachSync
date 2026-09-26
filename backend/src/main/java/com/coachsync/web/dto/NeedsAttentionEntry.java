package com.coachsync.web.dto;

import java.util.UUID;

/**
 * One athlete on the dashboard Needs-Attention list, with the negative signal(s)
 * that flagged them. At least one of {@code decliningBlock} /
 * {@code inconsistentPacing} is non-null.
 */
public record NeedsAttentionEntry(
        UUID athleteId,
        String firstName,
        String lastName,
        String decliningBlock,
        InconsistentPacing inconsistentPacing) {
}
