package com.coachsync.web;

import com.coachsync.domain.enums.SessionStatus;
import com.coachsync.service.SessionService;
import com.coachsync.web.dto.SessionRequest;
import com.coachsync.web.dto.SessionResponse;
import jakarta.validation.Valid;
import org.springframework.data.domain.Pageable;
import org.springframework.data.web.PagedModel;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import java.net.URI;
import java.time.LocalDate;
import java.util.UUID;

/**
 * CRUD for training sessions plus lifecycle toggles. {@code GET /api/sessions} is
 * paginated and filterable by status, team, date, and archived flag, and
 * {@code create} stamps the authoring coach from the JWT principal ({@code sub}).
 * {@code PATCH .../status} drives the Open → Completed/Cancelled lifecycle;
 * {@code PATCH .../archive} hides a completed session from the active dashboard
 * and schedule without deleting its history.
 */
@RestController
@RequestMapping("/api/sessions")
public class SessionController {

    private final SessionService service;

    public SessionController(SessionService service) {
        this.service = service;
    }

    @GetMapping
    public PagedModel<SessionResponse> list(
            @RequestParam(required = false) SessionStatus status,
            @RequestParam(required = false) UUID teamId,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date,
            @RequestParam(required = false) Boolean archived,
            Pageable pageable) {
        return new PagedModel<>(service.list(status, teamId, date, archived, pageable).map(SessionResponse::from));
    }

    @GetMapping("/{id}")
    public SessionResponse get(@PathVariable UUID id) {
        return SessionResponse.from(service.get(id));
    }

    /** Creates a session, stamping the authoring coach from the JWT principal. */
    @PostMapping
    public ResponseEntity<SessionResponse> create(@Valid @RequestBody SessionRequest request,
                                                  @AuthenticationPrincipal Jwt principal) {
        SessionResponse created = SessionResponse.from(
                service.create(request, UUID.fromString(principal.getSubject())));
        URI location = ServletUriComponentsBuilder.fromCurrentRequest()
                .path("/{id}").buildAndExpand(created.id()).toUri();
        return ResponseEntity.created(location).body(created);
    }

    @PutMapping("/{id}")
    public SessionResponse update(@PathVariable UUID id, @Valid @RequestBody SessionRequest request) {
        return SessionResponse.from(service.update(id, request));
    }

    /** Advances the session lifecycle (Open → Completed/Cancelled). */
    @PatchMapping("/{id}/status")
    public SessionResponse setStatus(@PathVariable UUID id, @RequestParam SessionStatus value) {
        return SessionResponse.from(service.setStatus(id, value));
    }

    /** Archives/unarchives a session — hides it from active views while preserving history. */
    @PatchMapping("/{id}/archive")
    public SessionResponse setArchived(@PathVariable UUID id, @RequestParam boolean value) {
        return SessionResponse.from(service.setArchived(id, value));
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable UUID id) {
        service.delete(id);
    }
}
