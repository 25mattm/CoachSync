package com.coachsync;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.time.Clock;
import java.time.ZoneId;

import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * Boots the full Spring context against in-memory H2 with
 * {@code ddl-auto=create-drop}. If any JPA mapping is invalid (bad relationship,
 * unresolvable column, broken derived-query method on a repository), the context
 * fails to start and this test fails — so it doubles as a mapping smoke test.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
class CoachSyncBackendApplicationTests {

    @Autowired private Clock clock;

    @Test
    void contextLoads() {
        // Intentionally empty: success == the persistence unit + repositories
        // wired up and Hibernate created the schema in H2.
    }

    @Test
    void productionClockIsPinnedToTheClubsTimezone() {
        // Every analytics/SeasonContext test injects its own Clock.fixed(..., UTC) for
        // determinism, so none of them would catch a regression back to
        // Clock.systemDefaultZone() (container-timezone-dependent). This asserts the real,
        // wired-up bean instead.
        assertEquals(ZoneId.of("America/Toronto"), clock.getZone());
    }
}
