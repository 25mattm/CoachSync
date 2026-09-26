package com.coachsync.service;

import com.coachsync.auth.ClubTenantResolver;
import com.coachsync.auth.OperatorGuard;
import com.coachsync.domain.Club;
import com.coachsync.domain.Coach;
import com.coachsync.repository.ClubRepository;
import com.coachsync.repository.CoachRepository;
import com.coachsync.web.dto.ClubRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.util.Locale;
import java.util.UUID;

/**
 * Club creation and the join-code side of the approval queue (the operator-approval side lives in
 * {@link CoachService#approve}). See the multi-club tenancy plan's settled slice 4 design.
 */
@Service
public class ClubService {

    /** Excludes visually-confusable characters (0/O, 1/I) from a code meant to be typed by hand. */
    private static final String JOIN_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private static final int JOIN_CODE_LENGTH = 8;
    private static final int MAX_JOIN_CODE_ATTEMPTS = 10;

    private final ClubRepository clubs;
    private final CoachRepository coaches;
    private final ClubTenantResolver tenant;
    private final OperatorGuard operatorGuard;
    private final SecureRandom random = new SecureRandom();

    public ClubService(ClubRepository clubs, CoachRepository coaches, ClubTenantResolver tenant,
                        OperatorGuard operatorGuard) {
        this.clubs = clubs;
        this.coaches = coaches;
        this.tenant = tenant;
        this.operatorGuard = operatorGuard;
    }

    /** Operator-only: creates a club with a fresh, unique join code. */
    @Transactional
    public Club create(ClubRequest request) {
        operatorGuard.requireOperator();
        Club club = new Club();
        club.setName(request.name());
        club.setJoinCode(generateUniqueJoinCode());
        return clubs.save(club);
    }

    /**
     * Any signed-in coach: registers intent to join the club behind {@code joinCode}. Does not grant
     * access — {@code coach.club} stays {@code null} until an operator approves. A coach who already
     * belongs to a club must not silently switch clubs through this path.
     *
     * <p>Also refuses a coach who already has a <em>pending</em> request. Without this, a coach could
     * silently swap {@code requestedClub} to a different club after an operator has already reviewed
     * their original request (seen via {@code GET /api/coaches/pending}) but before that operator's
     * {@code approve} call lands — granting membership in a club the operator never actually vetted
     * them for. There is deliberately no "cancel my request" escape hatch yet; an operator can still
     * reject a mistaken request by simply not approving it.
     */
    @Transactional
    public Coach join(String joinCode) {
        UUID callerId = tenant.currentCoachId()
                .orElseThrow(() -> new ForbiddenException("Sign in required."));
        Coach coach = coaches.findById(callerId)
                .orElseThrow(() -> new ForbiddenException("Sign in required."));
        if (coach.getClub() != null) {
            throw new ConflictException("You already belong to a club.");
        }
        if (coach.getRequestedClub() != null) {
            throw new ConflictException("You already have a pending club join request.");
        }
        Club club = clubs.findByJoinCode(normalize(joinCode))
                .orElseThrow(() -> new NotFoundException("No club with that join code."));
        coach.setRequestedClub(club);
        return coaches.save(coach);
    }

    private String generateUniqueJoinCode() {
        for (int attempt = 0; attempt < MAX_JOIN_CODE_ATTEMPTS; attempt++) {
            String candidate = randomJoinCode();
            if (clubs.findByJoinCode(candidate).isEmpty()) {
                return candidate;
            }
        }
        throw new IllegalStateException("Could not generate a unique club join code.");
    }

    private String randomJoinCode() {
        StringBuilder code = new StringBuilder(JOIN_CODE_LENGTH);
        for (int i = 0; i < JOIN_CODE_LENGTH; i++) {
            code.append(JOIN_CODE_ALPHABET.charAt(random.nextInt(JOIN_CODE_ALPHABET.length())));
        }
        return code.toString();
    }

    /** Join codes are case-insensitive and whitespace-tolerant — they're meant to be typed by hand. */
    private static String normalize(String joinCode) {
        return joinCode.trim().toUpperCase(Locale.ROOT);
    }
}
