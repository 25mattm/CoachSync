package com.coachsync.web;

import com.coachsync.service.NoteService;
import com.coachsync.web.dto.NoteCreateRequest;
import com.coachsync.web.dto.NoteResponse;
import com.coachsync.web.dto.NoteUpdateRequest;
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
 * Athlete- and session-scoped coach notes. Notes are listed under an athlete or a
 * session and created under a session; get/update/delete address a note by id.
 * {@code create} stamps the authoring coach from the JWT principal ({@code sub}).
 */
@RestController
public class NoteController {

    private final NoteService service;

    public NoteController(NoteService service) {
        this.service = service;
    }

    @GetMapping("/api/athletes/{athleteId}/notes")
    public List<NoteResponse> forAthlete(@PathVariable UUID athleteId) {
        return service.forAthlete(athleteId);
    }

    @GetMapping("/api/sessions/{sessionId}/notes")
    public List<NoteResponse> forSession(@PathVariable UUID sessionId) {
        return service.forSession(sessionId);
    }

    /** Creates a session note, stamping the authoring coach from the JWT principal. */
    @PostMapping("/api/sessions/{sessionId}/notes")
    public ResponseEntity<NoteResponse> create(
            @PathVariable UUID sessionId, @Valid @RequestBody NoteCreateRequest request,
            @AuthenticationPrincipal Jwt principal) {
        NoteResponse created = service.create(sessionId, request, UUID.fromString(principal.getSubject()));
        URI location = ServletUriComponentsBuilder.fromCurrentContextPath()
                .path("/api/notes/{id}").buildAndExpand(created.id()).toUri();
        return ResponseEntity.created(location).body(created);
    }

    @PutMapping("/api/notes/{id}")
    public NoteResponse update(@PathVariable UUID id, @Valid @RequestBody NoteUpdateRequest request) {
        return service.update(id, request);
    }

    @DeleteMapping("/api/notes/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable UUID id) {
        service.delete(id);
    }
}
