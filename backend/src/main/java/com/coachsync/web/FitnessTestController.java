package com.coachsync.web;

import com.coachsync.service.FitnessTestResultService;
import com.coachsync.web.dto.FitnessTestRequest;
import com.coachsync.web.dto.FitnessTestResponse;
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
 * Fitness-test results are listed/created under their athlete and addressed
 * directly for get/update/delete.
 */
@RestController
public class FitnessTestController {

    private final FitnessTestResultService service;

    public FitnessTestController(FitnessTestResultService service) {
        this.service = service;
    }

    @GetMapping("/api/athletes/{athleteId}/fitness-tests")
    public List<FitnessTestResponse> list(@PathVariable UUID athleteId) {
        return service.listForAthlete(athleteId);
    }

    @PostMapping("/api/athletes/{athleteId}/fitness-tests")
    public ResponseEntity<FitnessTestResponse> create(
            @PathVariable UUID athleteId, @Valid @RequestBody FitnessTestRequest request) {
        FitnessTestResponse created = service.create(athleteId, request);
        URI location = ServletUriComponentsBuilder.fromCurrentContextPath()
                .path("/api/fitness-tests/{id}").buildAndExpand(created.id()).toUri();
        return ResponseEntity.created(location).body(created);
    }

    @GetMapping("/api/fitness-tests/{id}")
    public FitnessTestResponse get(@PathVariable UUID id) {
        return service.get(id);
    }

    @PutMapping("/api/fitness-tests/{id}")
    public FitnessTestResponse update(@PathVariable UUID id, @Valid @RequestBody FitnessTestRequest request) {
        return service.update(id, request);
    }

    @DeleteMapping("/api/fitness-tests/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable UUID id) {
        service.delete(id);
    }
}
