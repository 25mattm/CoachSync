package com.coachsync.web;

import com.coachsync.service.TeamService;
import com.coachsync.web.dto.TeamMembershipRequest;
import com.coachsync.web.dto.TeamMembershipResponse;
import com.coachsync.web.dto.TeamRequest;
import com.coachsync.web.dto.TeamResponse;
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
import java.util.List;
import java.util.UUID;

/**
 * CRUD for teams plus their rosters. Teams are archived (hidden from active lists)
 * via {@code PATCH .../archive} rather than deleted. The nested {@code .../members}
 * endpoints manage {@link com.coachsync.domain.TeamMembership} records — a
 * historical link whose {@code leftDate == null} means the athlete is still on the
 * team.
 */
@RestController
@RequestMapping("/api/teams")
public class TeamController {

    private final TeamService service;

    public TeamController(TeamService service) {
        this.service = service;
    }

    @GetMapping
    public PagedModel<TeamResponse> list(
            @RequestParam(required = false) Boolean archived, Pageable pageable) {
        return new PagedModel<>(service.list(archived, pageable).map(TeamResponse::from));
    }

    @GetMapping("/{id}")
    public TeamResponse get(@PathVariable UUID id) {
        return TeamResponse.from(service.get(id));
    }

    @PostMapping
    public ResponseEntity<TeamResponse> create(@Valid @RequestBody TeamRequest request) {
        TeamResponse created = TeamResponse.from(service.create(request));
        URI location = ServletUriComponentsBuilder.fromCurrentRequest()
                .path("/{id}").buildAndExpand(created.id()).toUri();
        return ResponseEntity.created(location).body(created);
    }

    @PutMapping("/{id}")
    public TeamResponse update(@PathVariable UUID id, @Valid @RequestBody TeamRequest request) {
        return TeamResponse.from(service.update(id, request));
    }

    @PatchMapping("/{id}/archive")
    public TeamResponse setArchived(@PathVariable UUID id, @RequestParam boolean value) {
        return TeamResponse.from(service.setArchived(id, value));
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable UUID id) {
        service.delete(id);
    }

    // --- Memberships ----------------------------------------------------------

    /** Lists the team's memberships; {@code active=true} returns only current members. */
    @GetMapping("/{id}/members")
    public List<TeamMembershipResponse> roster(
            @PathVariable UUID id, @RequestParam(required = false) Boolean active) {
        return service.roster(id, active);
    }

    @PostMapping("/{id}/members")
    public ResponseEntity<TeamMembershipResponse> addMember(
            @PathVariable UUID id, @Valid @RequestBody TeamMembershipRequest request) {
        TeamMembershipResponse created = service.addMember(id, request);
        URI location = ServletUriComponentsBuilder.fromCurrentRequest()
                .path("/{membershipId}").buildAndExpand(created.id()).toUri();
        return ResponseEntity.created(location).body(created);
    }

    @PutMapping("/{id}/members/{membershipId}")
    public TeamMembershipResponse updateMember(
            @PathVariable UUID id, @PathVariable UUID membershipId,
            @Valid @RequestBody TeamMembershipRequest request) {
        return service.updateMembership(id, membershipId, request);
    }

    @DeleteMapping("/{id}/members/{membershipId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void removeMember(@PathVariable UUID id, @PathVariable UUID membershipId) {
        service.removeMember(id, membershipId);
    }
}
