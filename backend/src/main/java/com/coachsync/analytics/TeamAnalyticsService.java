package com.coachsync.analytics;

import com.coachsync.domain.CoachSession;
import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.enums.SessionStatus;
import com.coachsync.domain.enums.TrainingZone;
import com.coachsync.repository.CoachSessionRepository;
import com.coachsync.repository.SessionBlockRepository;
import com.coachsync.repository.TeamRepository;
import com.coachsync.service.NotFoundException;
import com.coachsync.web.dto.TeamLoadResponse;
import com.coachsync.web.dto.ZoneKm;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.EnumMap;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Read-only training-load analytics for a team. Ports the iOS TeamsView rules:
 * load counts the team's COMPLETED sessions; recovery-zone km is excluded; the
 * zone breakdown lists all six non-recovery zones in a fixed order (including
 * zeros). There is no per-athlete attendance filter — it is the team's load.
 */
@Service
public class TeamAnalyticsService {

    /** The six non-recovery zones, in display order (matches the app). */
    private static final List<TrainingZone> BREAKDOWN_ZONES = List.of(
            TrainingZone.GA_1, TrainingZone.GA_2, TrainingZone.E_1,
            TrainingZone.E_2, TrainingZone.AN_MIX, TrainingZone.ALACTIC);

    private final TeamRepository teams;
    private final CoachSessionRepository sessions;
    private final SessionBlockRepository blocks;
    private final Clock clock;

    public TeamAnalyticsService(TeamRepository teams,
                                CoachSessionRepository sessions,
                                SessionBlockRepository blocks,
                                Clock clock) {
        this.teams = teams;
        this.sessions = sessions;
        this.blocks = blocks;
        this.clock = clock;
    }

    @Transactional(readOnly = true)
    public TeamLoadResponse load(UUID teamId, Integer year) {
        if (!teams.existsById(teamId)) {
            throw new NotFoundException("No team with id " + teamId);
        }
        int seasonYear = year != null ? year : SeasonContext.currentYear(clock);

        // The team's COMPLETED sessions, keyed by id for block-date lookup.
        Map<UUID, CoachSession> completed = new HashMap<>();
        for (CoachSession session : sessions.findByTeamId(teamId)) {
            if (session.getStatus() == SessionStatus.COMPLETED) {
                completed.put(session.getId(), session);
            }
        }
        List<SessionBlock> sessionBlocks = completed.isEmpty()
                ? List.of()
                : blocks.findBySessionIdIn(completed.keySet());

        LocalDate today = LocalDate.now(clock);
        LocalDate weekStart = today.minusDays(7);

        List<SessionBlock> seasonalBlocks = new ArrayList<>();
        double weeklyKm = 0.0;
        for (SessionBlock block : sessionBlocks) {
            LocalDate date = completed.get(block.getSession().getId()).getScheduledDate();
            if (SeasonContext.inSeason(date, seasonYear)) {
                seasonalBlocks.add(block);
            }
            if (!date.isBefore(weekStart) && !date.isAfter(today)
                    && block.getTrainingZone() != TrainingZone.RECOVERY) {
                Double km = TrainingLoad.effectiveDistanceKm(block);
                if (km != null) {
                    weeklyKm += km;
                }
            }
        }

        double seasonalKm = TrainingLoad.loadKilometers(seasonalBlocks);

        Map<TrainingZone, Double> zoneKm = new EnumMap<>(TrainingZone.class);
        for (SessionBlock block : seasonalBlocks) {
            TrainingZone zone = block.getTrainingZone();
            if (zone == null || zone == TrainingZone.RECOVERY) {
                continue;
            }
            Double km = TrainingLoad.effectiveDistanceKm(block);
            if (km != null) {
                zoneKm.merge(zone, km, Double::sum);
            }
        }

        List<ZoneKm> zoneBreakdown = new ArrayList<>();
        for (TrainingZone zone : BREAKDOWN_ZONES) {
            zoneBreakdown.add(new ZoneKm(zone, round1(zoneKm.getOrDefault(zone, 0.0))));
        }

        return new TeamLoadResponse(teamId, seasonYear, round1(weeklyKm), round1(seasonalKm), zoneBreakdown);
    }

    private static double round1(double value) {
        return Math.round(value * 10.0) / 10.0;
    }
}
