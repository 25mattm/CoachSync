package com.coachsync.web;

import com.coachsync.analytics.TeamAnalyticsService;
import com.coachsync.web.dto.TeamLoadResponse;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/**
 * Read-only training-load analytics for a team. {@code year} defaults to the
 * current season (computed at request time); pass it for a historical season.
 */
@RestController
@RequestMapping("/api/teams/{teamId}")
public class TeamAnalyticsController {

    private final TeamAnalyticsService service;

    public TeamAnalyticsController(TeamAnalyticsService service) {
        this.service = service;
    }

    @GetMapping("/load")
    public TeamLoadResponse load(@PathVariable UUID teamId,
                                 @RequestParam(required = false) Integer year) {
        return service.load(teamId, year);
    }
}
