package com.coachsync.web;

import com.coachsync.service.KtcAssessmentService;
import com.coachsync.web.dto.KtcRequest;
import com.coachsync.web.dto.KtcResponse;
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
 * KTC assessments are listed/created under their athlete and addressed directly
 * for get/update/delete.
 */
@RestController
public class KtcController {

    private final KtcAssessmentService service;

    public KtcController(KtcAssessmentService service) {
        this.service = service;
    }

    @GetMapping("/api/athletes/{athleteId}/ktc")
    public List<KtcResponse> list(@PathVariable UUID athleteId) {
        return service.listForAthlete(athleteId);
    }

    @PostMapping("/api/athletes/{athleteId}/ktc")
    public ResponseEntity<KtcResponse> create(
            @PathVariable UUID athleteId, @Valid @RequestBody KtcRequest request) {
        KtcResponse created = service.create(athleteId, request);
        URI location = ServletUriComponentsBuilder.fromCurrentContextPath()
                .path("/api/ktc/{id}").buildAndExpand(created.id()).toUri();
        return ResponseEntity.created(location).body(created);
    }

    @GetMapping("/api/ktc/{id}")
    public KtcResponse get(@PathVariable UUID id) {
        return service.get(id);
    }

    @PutMapping("/api/ktc/{id}")
    public KtcResponse update(@PathVariable UUID id, @Valid @RequestBody KtcRequest request) {
        return service.update(id, request);
    }

    @DeleteMapping("/api/ktc/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable UUID id) {
        service.delete(id);
    }
}
