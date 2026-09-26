package com.coachsync.web;

import com.coachsync.domain.Club;
import com.coachsync.domain.Coach;
import com.coachsync.repository.ClubRepository;
import com.coachsync.repository.CoachRepository;
import org.springframework.boot.test.context.TestComponent;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import java.util.UUID;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/**
 * Shared club/coach fixtures for the multi-club tenancy MockMvc integration tests in this package —
 * the same "create a club, create a club-scoped coach, build a club-claim JWT" logic was previously
 * copy-pasted (with only cosmetic differences) across seven test classes. A fixture coach's email is
 * always on {@code coachsync.auth.allowed-emails} in test properties (required by
 * {@code ActiveCoachFilter}'s revocation check) and its {@code appleUserId} is always set (required
 * by {@code ActiveCoachFilter}'s "genuine coach" check) — every caller gets both for free.
 *
 * <p>A {@code @TestComponent}, not a regular {@code @Component}: it only ever joins a test's
 * application context via {@code @Import}, never production's.
 */
@TestComponent
public class ClubFixtures {

    private final CoachRepository coaches;
    private final ClubRepository clubs;

    public ClubFixtures(CoachRepository coaches, ClubRepository clubs) {
        this.coaches = coaches;
        this.clubs = clubs;
    }

    public record ClubFixture(UUID clubId, UUID coachId) {}

    /** A fresh club with one approved coach ("Pat") already in it. */
    public ClubFixture club() {
        return club("Pat");
    }

    /** As {@link #club()}, with a specific coach name — useful when a test asserts on it. */
    public ClubFixture club(String coachName) {
        Club club = new Club();
        club.setName("Club-" + UUID.randomUUID());
        UUID clubId = clubs.save(club).getId();
        Coach coach = new Coach();
        coach.setName(coachName);
        coach.setEmail("pat@example.com");
        coach.setAppleUserId("apple-" + UUID.randomUUID());
        coach.setClub(club);
        return new ClubFixture(clubId, coaches.save(coach).getId());
    }

    /** A JWT for the approved coach in {@code f}'s club. */
    public RequestPostProcessor token(ClubFixture f) {
        return jwt().jwt(j -> j.subject(f.coachId().toString()).claim("club", f.clubId().toString()));
    }

    /** A coach who exists but has never joined any club — genuinely pending, not just an unclaimed token. */
    public UUID pendingCoach() {
        Coach coach = new Coach();
        coach.setName("Pending");
        coach.setEmail("pat@example.com");
        coach.setAppleUserId("apple-pending-" + UUID.randomUUID());
        return coaches.save(coach).getId();
    }

    /** A token for a coach awaiting approval: authenticated, but with no club claim. */
    public RequestPostProcessor pendingToken(UUID coachId) {
        return jwt().jwt(j -> j.subject(coachId.toString()));
    }
}
