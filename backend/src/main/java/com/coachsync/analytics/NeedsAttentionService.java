package com.coachsync.analytics;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.PerformanceRecord;
import com.coachsync.domain.enums.RepEntryStatus;
import com.coachsync.repository.PerformanceRecordRepository;
import com.coachsync.web.dto.AthleteSignalsResponse;
import com.coachsync.web.dto.NeedsAttentionEntry;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * The dashboard "Needs Attention" list: up to five ACTIVE athletes carrying a
 * negative signal (declining or inconsistent pacing — most-improved is positive
 * and never qualifies). Mirrors the iOS NeedsAttentionSection. One query fetches
 * every athlete's COMPLETE rep results (with athlete + block + session); signals
 * are then computed in memory per athlete, so the scan is not a per-athlete N+1.
 */
@Service
public class NeedsAttentionService {

    private static final int MAX_ENTRIES = 5;

    private final PerformanceRecordRepository performance;
    private final AthleteSignalsService signals;

    public NeedsAttentionService(PerformanceRecordRepository performance, AthleteSignalsService signals) {
        this.performance = performance;
        this.signals = signals;
    }

    @Transactional(readOnly = true)
    public List<NeedsAttentionEntry> list() {
        // Group every active athlete's COMPLETE rep results from the single fetch.
        Map<UUID, List<PerformanceRecord>> byAthlete = new HashMap<>();
        Map<UUID, Athlete> athleteById = new HashMap<>();
        for (PerformanceRecord record : performance.findByStatus(RepEntryStatus.COMPLETE)) {
            Athlete athlete = record.getAthlete();
            if (athlete == null || !athlete.isActive() || record.getSessionBlock() == null) {
                continue;
            }
            byAthlete.computeIfAbsent(athlete.getId(), k -> new ArrayList<>()).add(record);
            athleteById.putIfAbsent(athlete.getId(), athlete);
        }

        List<NeedsAttentionEntry> flagged = new ArrayList<>();
        for (Map.Entry<UUID, List<PerformanceRecord>> entry : byAthlete.entrySet()) {
            AthleteSignalsResponse signal = signals.signalsFrom(entry.getKey(), entry.getValue());
            if (signal.decliningBlock() == null && signal.inconsistentPacing() == null) {
                continue;
            }
            Athlete athlete = athleteById.get(entry.getKey());
            flagged.add(new NeedsAttentionEntry(
                    athlete.getId(), athlete.getFirstName(), athlete.getLastName(),
                    signal.decliningBlock(), signal.inconsistentPacing()));
        }

        flagged.sort(Comparator
                .comparing(NeedsAttentionEntry::lastName, String.CASE_INSENSITIVE_ORDER)
                .thenComparing(NeedsAttentionEntry::firstName, String.CASE_INSENSITIVE_ORDER));
        return flagged.size() > MAX_ENTRIES ? List.copyOf(flagged.subList(0, MAX_ENTRIES)) : flagged;
    }
}
