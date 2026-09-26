package com.coachsync.web;

import com.coachsync.service.RegattaResultService;
import com.coachsync.web.dto.RegattaResultRequest;
import com.coachsync.web.dto.RegattaResultResponse;
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
 * Regatta results are listed/created under their athlete and addressed directly
 * for get/update/delete.
 */
@RestController
public class RegattaResultController {

    private final RegattaResultService service;

    public RegattaResultController(RegattaResultService service) {
        this.service = service;
    }

    @GetMapping("/api/athletes/{athleteId}/regatta-results")
    public List<RegattaResultResponse> list(@PathVariable UUID athleteId) {
        return service.listForAthlete(athleteId);
    }

    @PostMapping("/api/athletes/{athleteId}/regatta-results")
    public ResponseEntity<RegattaResultResponse> create(
            @PathVariable UUID athleteId, @Valid @RequestBody RegattaResultRequest request) {
        RegattaResultResponse created = service.create(athleteId, request);
        URI location = ServletUriComponentsBuilder.fromCurrentContextPath()
                .path("/api/regatta-results/{id}").buildAndExpand(created.id()).toUri();
        return ResponseEntity.created(location).body(created);
    }

    @GetMapping("/api/regatta-results/{id}")
    public RegattaResultResponse get(@PathVariable UUID id) {
        return service.get(id);
    }

    @PutMapping("/api/regatta-results/{id}")
    public RegattaResultResponse update(@PathVariable UUID id, @Valid @RequestBody RegattaResultRequest request) {
        return service.update(id, request);
    }

    @DeleteMapping("/api/regatta-results/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable UUID id) {
        service.delete(id);
    }
}
