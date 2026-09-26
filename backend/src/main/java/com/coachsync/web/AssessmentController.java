package com.coachsync.web;

import com.coachsync.service.TechnicalAssessmentService;
import com.coachsync.web.dto.AssessmentRequest;
import com.coachsync.web.dto.AssessmentResponse;
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
 * Technical assessments are listed/created under their athlete and addressed
 * directly for get/update/delete.
 */
@RestController
public class AssessmentController {

    private final TechnicalAssessmentService service;

    public AssessmentController(TechnicalAssessmentService service) {
        this.service = service;
    }

    @GetMapping("/api/athletes/{athleteId}/assessments")
    public List<AssessmentResponse> list(@PathVariable UUID athleteId) {
        return service.listForAthlete(athleteId);
    }

    @PostMapping("/api/athletes/{athleteId}/assessments")
    public ResponseEntity<AssessmentResponse> create(
            @PathVariable UUID athleteId, @Valid @RequestBody AssessmentRequest request) {
        AssessmentResponse created = service.create(athleteId, request);
        URI location = ServletUriComponentsBuilder.fromCurrentContextPath()
                .path("/api/assessments/{id}").buildAndExpand(created.id()).toUri();
        return ResponseEntity.created(location).body(created);
    }

    @GetMapping("/api/assessments/{id}")
    public AssessmentResponse get(@PathVariable UUID id) {
        return service.get(id);
    }

    @PutMapping("/api/assessments/{id}")
    public AssessmentResponse update(@PathVariable UUID id, @Valid @RequestBody AssessmentRequest request) {
        return service.update(id, request);
    }

    @DeleteMapping("/api/assessments/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable UUID id) {
        service.delete(id);
    }
}
