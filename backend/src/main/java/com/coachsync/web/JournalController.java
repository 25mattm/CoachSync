package com.coachsync.web;

import com.coachsync.service.DevelopmentNoteService;
import com.coachsync.web.dto.JournalRequest;
import com.coachsync.web.dto.JournalResponse;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
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
 * Development-journal entries are listed/created under their athlete and
 * addressed directly for get/update/delete.
 */
@RestController
public class JournalController {

    private final DevelopmentNoteService service;

    public JournalController(DevelopmentNoteService service) {
        this.service = service;
    }

    @GetMapping("/api/athletes/{athleteId}/journal")
    public List<JournalResponse> list(@PathVariable UUID athleteId) {
        return service.listForAthlete(athleteId);
    }

    @PostMapping("/api/athletes/{athleteId}/journal")
    public ResponseEntity<JournalResponse> create(
            @PathVariable UUID athleteId, @Valid @RequestBody JournalRequest request,
            @AuthenticationPrincipal Jwt principal) {
        JournalResponse created = service.create(athleteId, request, UUID.fromString(principal.getSubject()));
        URI location = ServletUriComponentsBuilder.fromCurrentContextPath()
                .path("/api/journal/{id}").buildAndExpand(created.id()).toUri();
        return ResponseEntity.created(location).body(created);
    }

    @GetMapping("/api/journal/{id}")
    public JournalResponse get(@PathVariable UUID id) {
        return service.get(id);
    }

    @PutMapping("/api/journal/{id}")
    public JournalResponse update(@PathVariable UUID id, @Valid @RequestBody JournalRequest request) {
        return service.update(id, request);
    }

    @DeleteMapping("/api/journal/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable UUID id) {
        service.delete(id);
    }
}
