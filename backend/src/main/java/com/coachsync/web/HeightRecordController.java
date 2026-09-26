package com.coachsync.web;

import com.coachsync.service.HeightRecordService;
import com.coachsync.web.dto.HeightRecordRequest;
import com.coachsync.web.dto.HeightRecordResponse;
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
 * Height records are listed/created under their athlete and addressed directly
 * for get/update/delete.
 */
@RestController
public class HeightRecordController {

    private final HeightRecordService service;

    public HeightRecordController(HeightRecordService service) {
        this.service = service;
    }

    @GetMapping("/api/athletes/{athleteId}/heights")
    public List<HeightRecordResponse> list(@PathVariable UUID athleteId) {
        return service.listForAthlete(athleteId);
    }

    @PostMapping("/api/athletes/{athleteId}/heights")
    public ResponseEntity<HeightRecordResponse> create(
            @PathVariable UUID athleteId, @Valid @RequestBody HeightRecordRequest request) {
        HeightRecordResponse created = service.create(athleteId, request);
        URI location = ServletUriComponentsBuilder.fromCurrentContextPath()
                .path("/api/heights/{id}").buildAndExpand(created.id()).toUri();
        return ResponseEntity.created(location).body(created);
    }

    @GetMapping("/api/heights/{id}")
    public HeightRecordResponse get(@PathVariable UUID id) {
        return service.get(id);
    }

    @PutMapping("/api/heights/{id}")
    public HeightRecordResponse update(@PathVariable UUID id, @Valid @RequestBody HeightRecordRequest request) {
        return service.update(id, request);
    }

    @DeleteMapping("/api/heights/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable UUID id) {
        service.delete(id);
    }
}
