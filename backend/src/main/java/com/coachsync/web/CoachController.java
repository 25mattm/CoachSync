package com.coachsync.web;

import com.coachsync.service.CoachService;
import com.coachsync.web.dto.CoachRequest;
import com.coachsync.web.dto.CoachResponse;
import com.coachsync.web.dto.PendingCoachResponse;
import jakarta.validation.Valid;
import org.springframework.data.domain.Pageable;
import org.springframework.data.web.PagedModel;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import java.net.URI;
import java.util.List;
import java.util.UUID;

/**
 * CRUD for coach profiles, plus the operator side of the approval queue ({@link #pending} and
 * {@link #approve}; the coach-facing join side is {@code POST /api/clubs/join} on
 * {@link ClubController}). {@code DELETE} is refused with 409 when the coach is
 * still attributed on any session, note, or journal entry
 * (see {@link com.coachsync.service.CoachService#delete}); reassign or remove
 * those first.
 */
@RestController
@RequestMapping("/api/coaches")
public class CoachController {

    private final CoachService service;

    public CoachController(CoachService service) {
        this.service = service;
    }

    @GetMapping
    public PagedModel<CoachResponse> list(Pageable pageable) {
        return new PagedModel<>(service.list(pageable).map(CoachResponse::from));
    }

    /** Operator-only: every coach awaiting approval, platform-wide. Must precede {@code /{id}}. */
    @GetMapping("/pending")
    public List<PendingCoachResponse> pending() {
        return service.pending().stream().map(PendingCoachResponse::from).toList();
    }

    @GetMapping("/{id}")
    public CoachResponse get(@PathVariable UUID id) {
        return CoachResponse.from(service.get(id));
    }

    @PostMapping
    public ResponseEntity<CoachResponse> create(@Valid @RequestBody CoachRequest request) {
        CoachResponse created = CoachResponse.from(service.create(request));
        URI location = ServletUriComponentsBuilder.fromCurrentRequest()
                .path("/{id}").buildAndExpand(created.id()).toUri();
        return ResponseEntity.created(location).body(created);
    }

    @PutMapping("/{id}")
    public CoachResponse update(@PathVariable UUID id, @Valid @RequestBody CoachRequest request) {
        return CoachResponse.from(service.update(id, request));
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable UUID id) {
        service.delete(id);
    }

    /** Operator-only: approves a pending coach into the club they requested via a join code. */
    @PostMapping("/{id}/approve")
    public CoachResponse approve(@PathVariable UUID id) {
        return CoachResponse.from(service.approve(id));
    }
}
