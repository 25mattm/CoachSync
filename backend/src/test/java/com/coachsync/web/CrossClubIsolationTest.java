package com.coachsync.web;

import com.coachsync.web.ClubFixtures.ClubFixture;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import java.util.UUID;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The acceptance gate for multi-club tenancy: a coach in club A must not be able to read, write,
 * update, delete or enumerate any row belonging to club B — through any endpoint.
 *
 * <p>Deliberately <b>not</b> {@code @Transactional}. Hibernate fixes the {@code _tenantId} filter
 * parameter when the session opens; a class-level test transaction would open that session before
 * MockMvc applies the request's JWT, so every row would be written and read under the same tenant
 * and the test would pass while proving nothing. Each request here opens its own session with its
 * own tenant. For the same reason each test uses a freshly-created club, so leftover rows from a
 * sibling test are invisible rather than needing cleanup.
 *
 * <p>The 404s below are the interesting assertions. They only hold because
 * {@code TenantIdBinder} registers its filter with {@code applyToLoadByKey = true}: an ordinary
 * Hibernate {@code @Filter} does not restrict load-by-primary-key, and every one of these
 * {@code /{id}} routes would silently succeed across clubs.
 *
 * <p>Each fixture coach's {@code Coach.club} is set to the exact club its token claims — since
 * slice 4, {@code ActiveCoachFilter} 401s any request whose {@code club} claim doesn't match the
 * coach's actual current club, so a token claiming a club the coach doesn't belong to would never
 * even reach these endpoints to prove isolation.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import(ClubFixtures.class)
class CrossClubIsolationTest {

    @Autowired private MockMvc mvc;
    @Autowired private ClubFixtures fixtures;

    private ClubFixture club() {
        return fixtures.club();
    }

    private UUID pendingCoach() {
        return fixtures.pendingCoach();
    }

    private RequestPostProcessor token(ClubFixture f) {
        return fixtures.token(f);
    }

    private RequestPostProcessor pendingToken(UUID coach) {
        return fixtures.pendingToken(coach);
    }

    private static final String ATHLETE = """
            {"firstName":"Ada","lastName":"Lovelace","dateOfBirth":"2014-05-01","gender":"FEMALE"}
            """;

    private String createAthleteIn(ClubFixture f) throws Exception {
        String body = mvc.perform(post("/api/athletes")
                        .with(token(f))
                        .contentType(MediaType.APPLICATION_JSON).content(ATHLETE))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return body.replaceAll("(?s).*\"id\"\\s*:\\s*\"([^\"]+)\".*", "$1");
    }

    @Test
    void clubBCannotSeeOrEnumerateClubAsAthletes() throws Exception {
        ClubFixture a = club();
        ClubFixture b = club();
        createAthleteIn(a);

        // Club A sees its own athlete.
        mvc.perform(get("/api/athletes").with(token(a)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content.length()").value(1));

        // Club B's roster is empty — findAll() was never scoped by hand, the filter did it.
        mvc.perform(get("/api/athletes").with(token(b)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content.length()").value(0));
    }

    @Test
    void clubBCannotReadUpdateOrDeleteClubAsAthleteById() throws Exception {
        ClubFixture a = club();
        ClubFixture b = club();
        String athleteId = createAthleteIn(a);

        // Load-by-primary-key is filtered too — this is the assertion that a plain @Filter fails.
        mvc.perform(get("/api/athletes/{id}", athleteId).with(token(b)))
                .andExpect(status().isNotFound());

        mvc.perform(put("/api/athletes/{id}", athleteId)
                        .with(token(b))
                        .contentType(MediaType.APPLICATION_JSON).content(ATHLETE))
                .andExpect(status().isNotFound());

        mvc.perform(delete("/api/athletes/{id}", athleteId).with(token(b)))
                .andExpect(status().isNotFound());

        // …and club A still has an intact, undeleted athlete.
        mvc.perform(get("/api/athletes/{id}", athleteId).with(token(a)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.firstName").value("Ada"));
    }

    @Test
    void coachAwaitingApprovalSeesNothing() throws Exception {
        ClubFixture a = club();
        String athleteId = createAthleteIn(a);
        UUID pending = pendingCoach();

        // No club claim -> ClubTenantResolver.NO_TENANT -> matches none of club A's rows. Asserts
        // club A's athlete specifically is absent rather than that the list is empty: NO_TENANT is a
        // fixed sentinel (not a per-test-random club id like the rest of this file). Reads alone can't
        // prove it's otherwise empty here — see pendingCoachCannotWriteToTenantScopedEndpoints below,
        // which is what actually proves no OTHER pending coach's write can land under this sentinel
        // anymore.
        mvc.perform(get("/api/athletes").with(pendingToken(pending)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content[?(@.id == '" + athleteId + "')]").doesNotExist());

        mvc.perform(get("/api/athletes/{id}", athleteId).with(pendingToken(pending)))
                .andExpect(status().isNotFound());
    }

    /**
     * {@code ClubMembershipWriteGuard} closes the gap this test used to pin as an accepted tradeoff
     * (a pending coach's write landing under the shared {@code NO_TENANT} sentinel, readable by any
     * other pending stranger — see {@code ClubTenantResolver.NO_TENANT}'s javadoc for the before/after).
     * A club-less caller's mutating request never reaches the controller at all now, so there is
     * nothing for a second pending coach to read back.
     */
    @Test
    void pendingCoachCannotWriteToTenantScopedEndpoints() throws Exception {
        UUID pendingA = pendingCoach();

        mvc.perform(post("/api/athletes")
                        .with(pendingToken(pendingA))
                        .contentType(MediaType.APPLICATION_JSON).content(ATHLETE))
                .andExpect(status().isForbidden());

        // Nothing was written — not merely rejected after the fact.
        mvc.perform(get("/api/athletes").with(pendingToken(pendingA)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content.length()").value(0));
    }

    /**
     * {@code ClubMembershipWriteGuard} is a single boundary filter, not 15 per-service guards — this
     * proves it actually reaches every shape of write route: a top-level POST, a child-route POST
     * nested under another aggregate, a top-level PUT, a lifecycle PATCH, and a bare-id child DELETE
     * (the same route shape {@link #clubBCannotReachClubAsChildRowsByBareId} proves the tenant filter
     * reaches). Also proves the {@code /api/coaches/*}{@code /approve} allowlist entry does not
     * accidentally widen into the rest of {@code /api/coaches/**} — a club-less caller still cannot
     * create a coach.
     */
    @Test
    void pendingCoachIsBlockedAcrossTheWriteSurface() throws Exception {
        ClubFixture a = club();
        String athleteId = createAthleteIn(a);
        String sessionId = mvc.perform(post("/api/sessions")
                        .with(token(a))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"sessionName\":\"Tuesday AM\",\"scheduledDate\":\"2026-06-16\"}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString()
                .replaceAll("(?s).*\"id\"\\s*:\\s*\"([^\"]+)\".*", "$1");
        String blockId = mvc.perform(post("/api/sessions/{sid}/blocks", sessionId)
                        .with(token(a))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"blockName\":\"8x200\",\"blockType\":\"PADDLE_DISTANCE\",\"repetitionCount\":3}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString()
                .replaceAll("(?s).*\"id\"\\s*:\\s*\"([^\"]+)\".*", "$1");

        UUID pending = pendingCoach();

        // Child-route POST, nested under another aggregate.
        mvc.perform(post("/api/athletes/{athleteId}/assessments", athleteId)
                        .with(pendingToken(pending))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"stage\":\"LTAD_2\"}"))
                .andExpect(status().isForbidden());

        // Top-level PUT.
        mvc.perform(put("/api/athletes/{id}", athleteId)
                        .with(pendingToken(pending))
                        .contentType(MediaType.APPLICATION_JSON).content(ATHLETE))
                .andExpect(status().isForbidden());

        // Lifecycle PATCH.
        mvc.perform(patch("/api/sessions/{id}/status", sessionId)
                        .param("value", "COMPLETED")
                        .with(pendingToken(pending)))
                .andExpect(status().isForbidden());

        // Bare-id child DELETE.
        mvc.perform(delete("/api/blocks/{id}", blockId).with(pendingToken(pending)))
                .andExpect(status().isForbidden());

        // The /api/coaches/*/approve allowlist entry must not widen into the rest of /api/coaches/**.
        mvc.perform(post("/api/coaches")
                        .with(pendingToken(pending))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Nope\",\"role\":\"ASSISTANT\"}"))
                .andExpect(status().isForbidden());

        // Nothing above actually landed.
        mvc.perform(get("/api/athletes/{athleteId}/assessments", athleteId).with(token(a)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(0));
    }

    /**
     * Children matter as much as roots. {@code /api/blocks/{id}} addresses a {@code SessionBlock} by
     * bare id with no session in the path, so scoping only the aggregate roots would leave every
     * block, rep result, note and assessment cross-club readable, writable and deletable.
     */
    @Test
    void clubBCannotReachClubAsChildRowsByBareId() throws Exception {
        ClubFixture a = club();
        ClubFixture b = club();

        String sessionId = mvc.perform(post("/api/sessions")
                        .with(token(a))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"sessionName\":\"Tuesday AM\",\"scheduledDate\":\"2026-06-16\"}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString()
                .replaceAll("(?s).*\"id\"\\s*:\\s*\"([^\"]+)\".*", "$1");

        String blockId = mvc.perform(post("/api/sessions/{sid}/blocks", sessionId)
                        .with(token(a))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"blockName\":\"8x200\",\"blockType\":\"PADDLE_DISTANCE\",\"repetitionCount\":3}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString()
                .replaceAll("(?s).*\"id\"\\s*:\\s*\"([^\"]+)\".*", "$1");

        // The child, by bare id.
        mvc.perform(get("/api/blocks/{id}", blockId).with(token(b)))
                .andExpect(status().isNotFound());
        mvc.perform(delete("/api/blocks/{id}", blockId).with(token(b)))
                .andExpect(status().isNotFound());

        // And the parent, so club B cannot enumerate club A's blocks through the sub-resource.
        mvc.perform(get("/api/sessions/{sid}/blocks", sessionId).with(token(b)))
                .andExpect(status().isNotFound());

        // Club A's block survived every one of those.
        mvc.perform(get("/api/blocks/{id}", blockId).with(token(a)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.blockName").value("8x200"));
    }

    /**
     * Since slice 4, a malformed claim never even reaches {@code ClubTenantResolver}'s own
     * malformed-claim fallback (NO_TENANT): {@code ActiveCoachFilter}'s revocation check rejects it
     * first — a string can never equal a real club's UUID, so it can never match the coach's actual
     * club and is revoked (401) rather than silently downgraded to an empty result set.
     */
    @Test
    void aMalformedClubClaimIsRejectedOutright() throws Exception {
        ClubFixture a = club();
        String athleteId = createAthleteIn(a);

        RequestPostProcessor garbage =
                jwt().jwt(j -> j.subject(a.coachId().toString()).claim("club", "not-a-uuid"));

        mvc.perform(get("/api/athletes/{id}", athleteId).with(garbage))
                .andExpect(status().isUnauthorized());
        mvc.perform(get("/api/athletes").with(garbage))
                .andExpect(status().isUnauthorized());
    }
}
