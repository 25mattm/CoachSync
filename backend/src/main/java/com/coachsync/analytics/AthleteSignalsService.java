package com.coachsync.analytics;

import com.coachsync.domain.KtcAssessment;
import com.coachsync.domain.PerformanceRecord;
import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.enums.RepEntryStatus;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.KtcAssessmentRepository;
import com.coachsync.repository.PerformanceRecordRepository;
import com.coachsync.service.NotFoundException;
import com.coachsync.web.dto.AthleteSignalsResponse;
import com.coachsync.web.dto.InconsistentPacing;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.OptionalDouble;
import java.util.UUID;
import java.util.function.DoublePredicate;
import java.util.function.Function;

/**
 * Read-only insight signals for one athlete — the backend port of the iOS
 * {@code InsightSignals} (declining / most-improved / inconsistent pacing). All
 * three look only at the athlete's COMPLETE timed rep results; attendance and
 * session status do not gate them.
 */
@Service
public class AthleteSignalsService {

    /** Slope (ms per session-step) at/above which a block is "declining". */
    private static final double DECLINING_SLOPE_MS = 50.0;
    /** Slope at/below which a block is "most improved" (times falling). */
    private static final double IMPROVING_SLOPE_MS = -50.0;
    /** CV above which rep-to-rep pacing is flagged inconsistent (0.10 = 10%). */
    private static final double PACING_CV_ALERT = 0.10;
    /** Average a block's CV over at most this many recent sessions. */
    private static final int RECENT_SESSIONS_FOR_CV = 5;
    /** Minimum timed sessions for a block before a regression slope is meaningful. */
    private static final int MIN_POINTS_FOR_REGRESSION = 3;
    /** Minimum sessions for a block before its averaged CV is meaningful. */
    private static final int MIN_SESSIONS_FOR_CV = 2;

    private final AthleteRepository athletes;
    private final PerformanceRecordRepository performance;
    private final KtcAssessmentRepository ktc;

    public AthleteSignalsService(AthleteRepository athletes,
                                 PerformanceRecordRepository performance,
                                 KtcAssessmentRepository ktc) {
        this.athletes = athletes;
        this.performance = performance;
        this.ktc = ktc;
    }

    @Transactional(readOnly = true)
    public AthleteSignalsResponse signals(UUID athleteId) {
        if (!athletes.existsById(athleteId)) {
            throw new NotFoundException("No athlete with id " + athleteId);
        }
        AthleteSignalsResponse base = signalsFrom(athleteId,
                performance.findByAthleteIdAndStatus(athleteId, RepEntryStatus.COMPLETE));
        return new AthleteSignalsResponse(athleteId, base.decliningBlock(), base.mostImprovedBlock(),
                base.inconsistentPacing(), ktcDecliningCount(athleteId));
    }

    /**
     * Computes the block-based signals from a pre-fetched batch of an athlete's
     * rep results. Lets the Needs-Attention scan reuse the algorithms without a
     * query per athlete. Records without a recorded time or a block are ignored.
     * {@code ktcDecliningCount} is left null here and filled by {@link #signals}.
     */
    public AthleteSignalsResponse signalsFrom(UUID athleteId, List<PerformanceRecord> records) {
        List<PerformanceRecord> complete = records.stream()
                .filter(r -> r.getRecordedTimeMs() != null && r.getSessionBlock() != null)
                .toList();
        return new AthleteSignalsResponse(
                athleteId,
                regressedBlockName(complete, slope -> slope > DECLINING_SLOPE_MS),
                regressedBlockName(complete, slope -> slope < IMPROVING_SLOPE_MS),
                inconsistentPacing(complete),
                null);
    }

    /**
     * The athlete's KTC-assessment count when their average-score trend is
     * declining (at least {@link #MIN_POINTS_FOR_REGRESSION} assessments and a
     * least-squares slope &lt; 0); otherwise null. Ports the iOS
     * {@code Athlete.ktcDecliningCount}. Runs in the caller's transaction.
     */
    private Integer ktcDecliningCount(UUID athleteId) {
        List<KtcAssessment> sorted = ktc.findByAthleteId(athleteId).stream()
                .sorted(Comparator.comparing(KtcAssessment::getDate))
                .toList();
        if (sorted.size() < MIN_POINTS_FOR_REGRESSION) {
            return null;
        }
        List<Double> scores = sorted.stream().map(AthleteSignalsService::ktcAverage).toList();
        OptionalDouble slope = InsightMath.leastSquaresSlope(scores);
        return slope.isPresent() && slope.getAsDouble() < 0 ? sorted.size() : null;
    }

    private static double ktcAverage(KtcAssessment k) {
        return (k.getSetupRecoveryScore() + k.getCatchScore()
                + k.getPropulsionDrawScore() + k.getExitScore()) / 4.0;
    }

    /**
     * The most recently trained block (by name) whose per-session mean COMPLETE rep
     * time, ordered by session date, regresses with a slope matching the predicate.
     * One point per session-block, so within-session fatigue and arbitrary rep order
     * can't read as a trend. Needs at least {@link #MIN_POINTS_FOR_REGRESSION} sessions
     * for that block name. Mirrors the iOS {@code regressedBlockName}; both run
     * {@code shared/fixtures/athlete-signals.json}.
     */
    private String regressedBlockName(List<PerformanceRecord> complete, DoublePredicate slopeMatches) {
        Map<String, List<SessionPoint>> byName = new HashMap<>();
        for (List<PerformanceRecord> group : groupBy(complete, r -> r.getSessionBlock().getId()).values()) {
            double mean = group.stream().mapToDouble(r -> (double) r.getRecordedTimeMs()).average().orElse(0.0);
            PerformanceRecord any = group.get(0);
            byName.computeIfAbsent(blockName(any), k -> new ArrayList<>())
                    .add(new SessionPoint(sessionDate(any), mean));
        }

        String best = null;
        LocalDate bestDate = null;
        for (Map.Entry<String, List<SessionPoint>> entry : byName.entrySet()) {
            List<SessionPoint> sessions = new ArrayList<>(entry.getValue());
            if (sessions.size() < MIN_POINTS_FOR_REGRESSION) {
                continue;
            }
            sessions.sort(Comparator.comparing(SessionPoint::date));
            List<Double> means = sessions.stream().map(SessionPoint::meanMs).toList();
            OptionalDouble slope = InsightMath.leastSquaresSlope(means);
            if (slope.isEmpty() || !slopeMatches.test(slope.getAsDouble())) {
                continue;
            }
            LocalDate mostRecent = sessions.get(sessions.size() - 1).date();
            if (bestDate == null || mostRecent.isAfter(bestDate)) {
                bestDate = mostRecent;
                best = entry.getKey();
            }
        }
        return best;
    }

    /**
     * The block with the worst average rep-to-rep CV over its recent sessions,
     * when that average exceeds the alert threshold. CV is computed per session
     * (needs >= 2 reps), then averaged over the most recent sessions per block.
     */
    private InconsistentPacing inconsistentPacing(List<PerformanceRecord> complete) {
        // One CV sample per session-block (the reps of one block on one date).
        Map<String, List<BlockCv>> byName = new HashMap<>();
        for (List<PerformanceRecord> group : groupBy(complete, r -> r.getSessionBlock().getId()).values()) {
            List<Double> times = group.stream().map(r -> (double) r.getRecordedTimeMs()).toList();
            OptionalDouble cv = InsightMath.coefficientOfVariation(times);
            if (cv.isEmpty()) {
                continue;
            }
            PerformanceRecord any = group.get(0);
            byName.computeIfAbsent(blockName(any), k -> new ArrayList<>())
                    .add(new BlockCv(sessionDate(any), cv.getAsDouble()));
        }

        String worstName = null;
        double worstAvg = -1.0;
        for (Map.Entry<String, List<BlockCv>> entry : byName.entrySet()) {
            List<BlockCv> samples = new ArrayList<>(entry.getValue());
            samples.sort(Comparator.comparing(BlockCv::date).reversed());
            List<BlockCv> recent = samples.size() > RECENT_SESSIONS_FOR_CV
                    ? samples.subList(0, RECENT_SESSIONS_FOR_CV)
                    : samples;
            if (recent.size() < MIN_SESSIONS_FOR_CV) {
                continue;
            }
            double avg = recent.stream().mapToDouble(BlockCv::cv).average().orElse(0.0);
            if (avg > PACING_CV_ALERT && avg > worstAvg) {
                worstAvg = avg;
                worstName = entry.getKey();
            }
        }
        return worstName == null ? null : new InconsistentPacing(worstName, (int) Math.round(worstAvg * 100.0));
    }

    private String blockName(PerformanceRecord record) {
        SessionBlock block = record.getSessionBlock();
        return block.getBlockName() != null ? block.getBlockName() : "Unknown";
    }

    private LocalDate sessionDate(PerformanceRecord record) {
        return record.getSessionBlock().getSession().getScheduledDate();
    }

    private static <K> Map<K, List<PerformanceRecord>> groupBy(
            List<PerformanceRecord> records, Function<PerformanceRecord, K> key) {
        Map<K, List<PerformanceRecord>> map = new HashMap<>();
        for (PerformanceRecord record : records) {
            map.computeIfAbsent(key.apply(record), k -> new ArrayList<>()).add(record);
        }
        return map;
    }

    /** One per-session CV sample for a block. */
    private record BlockCv(LocalDate date, double cv) {
    }

    /** One per-session mean rep time for a block (a regression point). */
    private record SessionPoint(LocalDate date, double meanMs) {
    }
}
