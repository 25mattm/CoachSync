package com.coachsync.web;

import com.coachsync.analytics.AthleteAnalyticsService;
import com.coachsync.analytics.AthleteSignalsService;
import com.coachsync.analytics.DevelopmentCoverageService;
import com.coachsync.analytics.FitnessBenchmarkService;
import com.coachsync.analytics.GrowthAnalyticsService;
import com.coachsync.web.dto.AthleteLoadResponse;
import com.coachsync.web.dto.AthleteSignalsResponse;
import com.coachsync.web.dto.DevelopmentCoverageEntry;
import com.coachsync.web.dto.FitnessBenchmarkEntry;
import com.coachsync.web.dto.GrowthVelocityResponse;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * Read-only analytics for a single athlete: training load, insight signals, and
 * development coverage. {@code year} defaults to the current season (computed at
 * request time); pass it explicitly for a historical season.
 */
@RestController
@RequestMapping("/api/athletes/{athleteId}")
public class AthleteAnalyticsController {

    private final AthleteAnalyticsService loadService;
    private final AthleteSignalsService signalsService;
    private final DevelopmentCoverageService coverageService;
    private final GrowthAnalyticsService growthService;
    private final FitnessBenchmarkService benchmarkService;

    public AthleteAnalyticsController(AthleteAnalyticsService loadService,
                                      AthleteSignalsService signalsService,
                                      DevelopmentCoverageService coverageService,
                                      GrowthAnalyticsService growthService,
                                      FitnessBenchmarkService benchmarkService) {
        this.loadService = loadService;
        this.signalsService = signalsService;
        this.coverageService = coverageService;
        this.growthService = growthService;
        this.benchmarkService = benchmarkService;
    }

    @GetMapping("/load")
    public AthleteLoadResponse load(@PathVariable UUID athleteId,
                                    @RequestParam(required = false) Integer year) {
        return loadService.load(athleteId, year);
    }

    @GetMapping("/signals")
    public AthleteSignalsResponse signals(@PathVariable UUID athleteId) {
        return signalsService.signals(athleteId);
    }

    @GetMapping("/development-coverage")
    public List<DevelopmentCoverageEntry> developmentCoverage(@PathVariable UUID athleteId) {
        return coverageService.coverage(athleteId);
    }

    @GetMapping("/growth-velocity")
    public GrowthVelocityResponse growthVelocity(@PathVariable UUID athleteId) {
        return growthService.growthVelocity(athleteId);
    }

    @GetMapping("/fitness-benchmarks")
    public List<FitnessBenchmarkEntry> fitnessBenchmarks(@PathVariable UUID athleteId,
                                                         @RequestParam(required = false) Integer year) {
        return benchmarkService.benchmarks(athleteId, year);
    }
}
