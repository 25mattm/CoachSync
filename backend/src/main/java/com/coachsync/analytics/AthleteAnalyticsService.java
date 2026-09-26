package com.coachsync.analytics;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.AttendanceRecord;
import com.coachsync.domain.CoachSession;
import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.enums.AttendanceStatus;
import com.coachsync.domain.enums.BlockType;
import com.coachsync.domain.enums.SessionStatus;
import com.coachsync.domain.enums.TrainingZone;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.AttendanceRecordRepository;
import com.coachsync.repository.SessionBlockRepository;
import com.coachsync.service.NotFoundException;
import com.coachsync.web.dto.AthleteLoadResponse;
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
import java.util.Set;
import java.util.UUID;

/**
 * Read-only training-load analytics for a single athlete. Ports the iOS
 * {@code LoadSection} rules: load counts COMPLETED sessions the athlete attended
 * PRESENT (deduped by session id); recovery-zone km is excluded; the LTAD bar
 * measures paddling km only, against the age category's yearly target.
 */
@Service
public class AthleteAnalyticsService {

    /** On-water block types — the only km that advance the LTAD bar. */
    private static final Set<BlockType> PADDLE_TYPES = Set.of(
            BlockType.PADDLE_DISTANCE, BlockType.PADDLE_TIME_PIECES, BlockType.PADDLE_PYRAMID);

    private final AthleteRepository athletes;
    private final AttendanceRecordRepository attendance;
    private final SessionBlockRepository blocks;
    private final Clock clock;

    public AthleteAnalyticsService(AthleteRepository athletes,
                                   AttendanceRecordRepository attendance,
                                   SessionBlockRepository blocks,
                                   Clock clock) {
        this.athletes = athletes;
        this.attendance = attendance;
        this.blocks = blocks;
        this.clock = clock;
    }

    @Transactional(readOnly = true)
    public AthleteLoadResponse load(UUID athleteId, Integer year) {
        Athlete athlete = athletes.findById(athleteId)
                .orElseThrow(() -> new NotFoundException("No athlete with id " + athleteId));
        int seasonYear = year != null ? year : SeasonContext.currentYear(clock);

        // Completed sessions the athlete attended PRESENT, deduped by session id.
        Map<UUID, CoachSession> completed = new HashMap<>();
        for (AttendanceRecord record : attendance.findByAthleteIdAndStatus(athleteId, AttendanceStatus.PRESENT)) {
            CoachSession session = record.getSession();
            if (session.getStatus() == SessionStatus.COMPLETED) {
                completed.putIfAbsent(session.getId(), session);
            }
        }

        // All blocks of those sessions in one query (no per-session N+1).
        List<SessionBlock> sessionBlocks = completed.isEmpty()
                ? List.of()
                : blocks.findBySessionIdIn(completed.keySet());

        LocalDate today = LocalDate.now(clock);
        LocalDate weekStart = today.minusDays(7);

        // Single pass: collect this season's blocks and accumulate weekly km.
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

        // Paddle-only km (LTAD) + per-zone breakdown, both over the season's blocks.
        double seasonalPaddleKm = 0.0;
        Map<TrainingZone, Double> zoneKm = new EnumMap<>(TrainingZone.class);
        for (SessionBlock block : seasonalBlocks) {
            if (block.getTrainingZone() == TrainingZone.RECOVERY) {
                continue;
            }
            Double km = TrainingLoad.effectiveDistanceKm(block);
            if (km == null) {
                continue;
            }
            if (block.getTrainingZone() != null) {
                zoneKm.merge(block.getTrainingZone(), km, Double::sum);
            }
            if (PADDLE_TYPES.contains(block.getBlockType())) {
                seasonalPaddleKm += km;
            }
        }

        String ageCategory = SeasonContext.ageCategory(athlete.getDateOfBirth(), seasonYear);
        SeasonContext.LtadTarget target = SeasonContext.ltadKmTarget(ageCategory);
        double progressPct = target.maxKm() <= 0
                ? 0.0
                : round1(Math.min(seasonalPaddleKm / target.maxKm(), 1.0) * 100.0);

        List<ZoneKm> zoneBreakdown = new ArrayList<>();
        for (Map.Entry<TrainingZone, Double> entry : zoneKm.entrySet()) {
            zoneBreakdown.add(new ZoneKm(entry.getKey(), round1(entry.getValue())));
        }

        return new AthleteLoadResponse(
                athleteId, seasonYear, ageCategory,
                round1(weeklyKm), round1(seasonalKm), round1(seasonalPaddleKm),
                target.minKm(), target.maxKm(), progressPct, zoneBreakdown);
    }

    /** Round to one decimal place so km/percent totals serialize cleanly. */
    private static double round1(double value) {
        return Math.round(value * 10.0) / 10.0;
    }
}
