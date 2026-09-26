package com.coachsync.web;

import com.coachsync.analytics.NeedsAttentionService;
import com.coachsync.web.dto.NeedsAttentionEntry;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/** Dashboard analytics: the Needs-Attention list (up to five flagged athletes). */
@RestController
@RequestMapping("/api/analytics")
public class NeedsAttentionController {

    private final NeedsAttentionService service;

    public NeedsAttentionController(NeedsAttentionService service) {
        this.service = service;
    }

    @GetMapping("/needs-attention")
    public List<NeedsAttentionEntry> needsAttention() {
        return service.list();
    }
}
