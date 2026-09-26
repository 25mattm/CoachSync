package com.coachsync.web;

import com.coachsync.service.PerformanceService;
import com.coachsync.web.dto.PerformanceRequest;
import com.coachsync.web.dto.PerformanceResponse;
import com.coachsync.web.dto.PerformanceUpsertRequest;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * Per-rep performance results. Results are listed under their block and recorded
 * individually by id; the block-scoped {@code PUT} is a natural-key upsert used by
 * the app↔backend sync path.
 */
@RestController
public class PerformanceController {

    private final PerformanceService performanceService;

    public PerformanceController(PerformanceService performanceService) {
        this.performanceService = performanceService;
    }

    @GetMapping("/api/blocks/{blockId}/performance")
    public List<PerformanceResponse> list(@PathVariable UUID blockId) {
        return performanceService.listForBlock(blockId);
    }

    @PutMapping("/api/performance/{id}")
    public PerformanceResponse record(@PathVariable UUID id, @Valid @RequestBody PerformanceRequest request) {
        return performanceService.record(id, request);
    }

    /** Natural-key rep-result upsert for a block — the app↔backend sync path. */
    @PutMapping("/api/blocks/{blockId}/performance")
    public List<PerformanceResponse> upsert(
            @PathVariable UUID blockId, @Valid @RequestBody PerformanceUpsertRequest request) {
        return performanceService.upsertForBlock(blockId, request);
    }
}
