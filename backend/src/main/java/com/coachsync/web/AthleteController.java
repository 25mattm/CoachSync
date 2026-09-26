package com.coachsync.web;

import com.coachsync.service.AthleteService;
import com.coachsync.web.dto.AthleteRequest;
import com.coachsync.web.dto.AthleteResponse;
import jakarta.validation.Valid;
import org.springframework.data.domain.Pageable;
import org.springframework.data.web.PagedModel;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
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
import java.util.UUID;

/**
 * CRUD for athletes. {@code GET /api/athletes} is paginated and filterable by
 * {@code active}; {@code PATCH /api/athletes/{id}/active} flips the active flag —
 * the soft-delete coaches use instead of deleting. A hard {@code DELETE} is
 * refused with 409 when the athlete has recorded history
 * (see {@link com.coachsync.service.AthleteHistoryGuard}); deactivate instead.
 */
@RestController
@RequestMapping("/api/athletes")
public class AthleteController {

    private final AthleteService service;

    public AthleteController(AthleteService service) {
        this.service = service;
    }

    @GetMapping
    public PagedModel<AthleteResponse> list(
            @RequestParam(required = false) Boolean active, Pageable pageable) {
        return new PagedModel<>(service.list(active, pageable).map(AthleteResponse::from));
    }

    @GetMapping("/{id}")
    public AthleteResponse get(@PathVariable UUID id) {
        return AthleteResponse.from(service.get(id));
    }

    @PostMapping
    public ResponseEntity<AthleteResponse> create(@Valid @RequestBody AthleteRequest request) {
        AthleteResponse created = AthleteResponse.from(service.create(request));
        URI location = ServletUriComponentsBuilder.fromCurrentRequest()
                .path("/{id}").buildAndExpand(created.id()).toUri();
        return ResponseEntity.created(location).body(created);
    }

    @PutMapping("/{id}")
    public AthleteResponse update(@PathVariable UUID id, @Valid @RequestBody AthleteRequest request) {
        return AthleteResponse.from(service.update(id, request));
    }

    /** Activates or deactivates the athlete — the soft-delete used in place of deletion. */
    @PatchMapping("/{id}/active")
    public AthleteResponse setActive(@PathVariable UUID id, @RequestParam boolean value) {
        return AthleteResponse.from(service.setActive(id, value));
    }

    /** Hard delete; refused with 409 when the athlete has recorded history. */
    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable UUID id) {
        service.delete(id);
    }
}
