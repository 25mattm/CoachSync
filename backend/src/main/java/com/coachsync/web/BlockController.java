package com.coachsync.web;

import com.coachsync.service.BlockService;
import com.coachsync.service.ReconcileCoordinator;
import com.coachsync.web.dto.BlockRequest;
import com.coachsync.web.dto.BlockResponse;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import java.net.URI;
import java.util.List;
import java.util.UUID;

/**
 * Blocks are listed/created under their session and addressed directly for
 * update/delete. After a create or edit (committed by {@link BlockService}) the
 * controller re-runs slot reconciliation via {@link ReconcileCoordinator} (its
 * own transaction + retry on a concurrent-reconcile race).
 */
@RestController
public class BlockController {

    private final BlockService blockService;
    private final ReconcileCoordinator reconcile;

    public BlockController(BlockService blockService, ReconcileCoordinator reconcile) {
        this.blockService = blockService;
        this.reconcile = reconcile;
    }

    @GetMapping("/api/sessions/{sessionId}/blocks")
    public List<BlockResponse> list(@PathVariable UUID sessionId) {
        return blockService.listForSession(sessionId);
    }

    @PostMapping("/api/sessions/{sessionId}/blocks")
    public ResponseEntity<BlockResponse> create(
            @PathVariable UUID sessionId, @Valid @RequestBody BlockRequest request) {
        BlockResponse created = blockService.create(sessionId, request);
        reconcile.reconcile(created.sessionId());
        URI location = ServletUriComponentsBuilder.fromCurrentContextPath()
                .path("/api/blocks/{id}").buildAndExpand(created.id()).toUri();
        return ResponseEntity.created(location).body(created);
    }

    @GetMapping("/api/blocks/{id}")
    public BlockResponse get(@PathVariable UUID id) {
        return blockService.get(id);
    }

    @PutMapping("/api/blocks/{id}")
    public BlockResponse update(@PathVariable UUID id, @Valid @RequestBody BlockRequest request) {
        BlockResponse updated = blockService.update(id, request);
        reconcile.reconcile(updated.sessionId());
        return updated;
    }

    @DeleteMapping("/api/blocks/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable UUID id) {
        blockService.delete(id);
    }
}
