package com.coachsync.analytics;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.FitnessTestResult;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.FitnessTestResultRepository;
import com.coachsync.service.NotFoundException;
import com.coachsync.web.dto.FitnessBenchmarkEntry;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.OptionalDouble;
import java.util.UUID;

/**
 * Read-only fitness-test benchmark analytics: an athlete's best (fastest) result
 * per test against the LTAD benchmark for their gender + age. Only benchmarked
 * tests the athlete has results for are returned; no gender → empty.
 */
@Service
public class FitnessBenchmarkService {

    private final AthleteRepository athletes;
    private final FitnessTestResultRepository tests;
    private final Clock clock;

    public FitnessBenchmarkService(AthleteRepository athletes,
                                   FitnessTestResultRepository tests,
                                   Clock clock) {
        this.athletes = athletes;
        this.tests = tests;
        this.clock = clock;
    }

    @Transactional(readOnly = true)
    public List<FitnessBenchmarkEntry> benchmarks(UUID athleteId, Integer year) {
        Athlete athlete = athletes.findById(athleteId)
                .orElseThrow(() -> new NotFoundException("No athlete with id " + athleteId));
        if (athlete.getGender() == null) {
            return List.of();
        }
        int seasonYear = year != null ? year : SeasonContext.currentYear(clock);
        int age = SeasonContext.athleteAge(athlete.getDateOfBirth(), seasonYear);

        // Best (lowest = fastest) result per test type.
        Map<String, Double> bestByType = new HashMap<>();
        for (FitnessTestResult test : tests.findByAthleteId(athleteId)) {
            bestByType.merge(test.getTestType(), test.getResult(), Math::min);
        }

        List<FitnessBenchmarkEntry> entries = new ArrayList<>();
        for (Map.Entry<String, Double> best : bestByType.entrySet()) {
            OptionalDouble benchmark = FitnessBenchmarks.benchmarkSeconds(athlete.getGender(), age, best.getKey());
            if (benchmark.isEmpty()) {
                continue;
            }
            double pct = round1(best.getValue() / benchmark.getAsDouble() * 100.0);
            entries.add(new FitnessBenchmarkEntry(best.getKey(), best.getValue(), benchmark.getAsDouble(), pct));
        }
        entries.sort(Comparator.comparing(FitnessBenchmarkEntry::testType));
        return entries;
    }

    private static double round1(double value) {
        return Math.round(value * 10.0) / 10.0;
    }
}
