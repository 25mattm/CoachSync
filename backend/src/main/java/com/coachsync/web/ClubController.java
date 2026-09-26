package com.coachsync.web;

import com.coachsync.service.ClubService;
import com.coachsync.web.dto.ClubRequest;
import com.coachsync.web.dto.ClubResponse;
import com.coachsync.web.dto.CoachResponse;
import com.coachsync.web.dto.JoinClubRequest;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Club creation and joining. {@code POST /api/clubs} is operator-only ({@link ClubService#create});
 * {@code POST /api/clubs/join} is open to any signed-in coach and only ever registers intent — see
 * {@link ClubService#join}. Approval (which actually grants access) is on
 * {@code POST /api/coaches/{id}/approve} ({@link com.coachsync.web.CoachController#approve}).
 */
@RestController
@RequestMapping("/api/clubs")
public class ClubController {

    private final ClubService service;

    public ClubController(ClubService service) {
        this.service = service;
    }

    @PostMapping
    public ResponseEntity<ClubResponse> create(@Valid @RequestBody ClubRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(ClubResponse.from(service.create(request)));
    }

    @PostMapping("/join")
    public CoachResponse join(@Valid @RequestBody JoinClubRequest request) {
        return CoachResponse.from(service.join(request.joinCode()));
    }
}
