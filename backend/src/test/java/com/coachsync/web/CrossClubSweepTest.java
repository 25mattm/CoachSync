package com.coachsync.web;

import com.coachsync.web.ClubFixtures.ClubFixture;
import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.request.RequestPostProcessor;
import org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerMapping;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.function.Function;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.request;

/**
 * Breadth companion to {@link CrossClubIsolationTest}. That class proves the tenant filter's
 * mechanism on a few representative routes; this one runs every {@code /api/**} route as club B
 * against a club A that owns one of everything, so a route that bypasses the filter (a hand-rolled
 * query, an unscoped table, a service that resolves an id some other way) shows up here.
 *
 * <p>Three checks per run:
 * <ul>
 *   <li>Every write from club B aimed at a club A id is refused with 403/404.</li>
 *   <li>Every read from club B is refused, or succeeds without a single club A id in the body.</li>
 *   <li>Club A's view of every read route is byte-identical before and after club B's attempts, so a
 *       write that answered 404 but mutated anyway is still caught.</li>
 * </ul>
 *
 * <p>{@link #everyApiRouteIsSweptOrExplicitlyExempt} keeps {@link #SWEEP} honest: a new controller
 * route fails the build until it is added here or to {@link #EXEMPT} with the reason it is safe.
 *
 * <p>Not {@code @Transactional} (see {@link CrossClubIsolationTest}); fresh club ids per run.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import(ClubFixtures.class)
class CrossClubSweepTest {

    @Autowired private MockMvc mvc;
    @Autowired private ClubFixtures fixtures;
    @Autowired @Qualifier("requestMappingHandlerMapping") private RequestMappingHandlerMapping mappings;

    /** One route, the club A ids that fill its template, and the body club B sends to it. */
    private record Route(HttpMethod method, String template, Function<Ids, Object[]> vars,
                         Function<Ids, String> body, Map<String, String> params) {

        String key() {
            return method.name() + " " + template;
        }

        boolean isRead() {
            return method == HttpMethod.GET;
        }
    }

    private static Route get(String template, Function<Ids, Object[]> vars) {
        return new Route(HttpMethod.GET, template, vars, null, Map.of());
    }

    private static Route write(HttpMethod method, String template, Function<Ids, Object[]> vars,
                               Function<Ids, String> body) {
        return new Route(method, template, vars, body, Map.of());
    }

    private static Route patch(String template, Function<Ids, Object[]> vars, String param, String value) {
        return new Route(HttpMethod.PATCH, template, vars, null, Map.of(param, value));
    }

    private static Object[] none(Ids ids) {
        return new Object[0];
    }

    /** Every club A row the sweep aims at. */
    private record Ids(String coach, String athlete, String team, String membership, String session,
                       String block, String note, String assessment, String height, String fitnessTest,
                       String regatta, String ktc, String journal, String performance) {

        List<String> all() {
            return List.of(coach, athlete, team, membership, session, block, note, assessment, height,
                    fitnessTest, regatta, ktc, journal, performance);
        }
    }

    private static final String ATHLETE = """
            {"firstName":"Ada","lastName":"Lovelace","dateOfBirth":"2014-05-01","gender":"FEMALE"}""";
    private static final String SESSION = """
            {"sessionName":"Tuesday AM","scheduledDate":"2026-06-16"}""";
    private static final String BLOCK = """
            {"blockName":"8x200","blockType":"PADDLE_DISTANCE","repetitionCount":3}""";
    private static final String TEAM = """
            {"teamName":"U14"}""";
    private static final String ASSESSMENT = """
            {"date":"2026-06-16","ratings":[{"category":"Balance","factor":"Posture","score":4}]}""";
    private static final String HEIGHT = """
            {"heightCm":162.5,"date":"2026-06-16"}""";
    private static final String FITNESS = """
            {"testType":"2km erg","result":480.5,"unit":"seconds","testDate":"2026-06-16"}""";
    private static final String REGATTA = """
            {"regattaName":"Nationals","location":"Welland","regattaDate":"2026-07-01","eventDistanceMetres":500,\
            "placement":2,"totalCompetitors":12,"resultTimeMs":120500}""";
    private static final String KTC = """
            {"date":"2026-06-16","window":"Pre-Competition","setupRecoveryScore":4,"catchScore":3,\
            "propulsionDrawScore":2,"exitScore":5,"notes":"solid"}""";
    private static final String JOURNAL = """
            {"date":"2026-06-16","text":"Strong week","tags":["Technique"]}""";
    private static final String COACH = """
            {"name":"Mallory","role":"ASSISTANT"}""";

    private static String member(Ids ids) {
        return "{\"athleteId\":\"" + ids.athlete() + "\"}";
    }

    private static String note(Ids ids) {
        return "{\"athleteId\":\"" + ids.athlete() + "\",\"noteText\":\"Strong catch\"}";
    }

    private static String attendance(Ids ids) {
        return "{\"entries\":[{\"athleteId\":\"" + ids.athlete() + "\",\"status\":\"PRESENT\"}]}";
    }

    private static String performance(Ids ids) {
        return "{\"entries\":[{\"athleteId\":\"" + ids.athlete()
                + "\",\"repNumber\":1,\"status\":\"COMPLETE\",\"recordedTimeMs\":1000}]}";
    }

    /** Every tenant-reachable route, aimed at club A's rows. */
    private static final List<Route> SWEEP = List.of(
            // Athletes
            get("/api/athletes", CrossClubSweepTest::none),
            get("/api/athletes/{id}", i -> new Object[]{i.athlete()}),
            write(HttpMethod.PUT, "/api/athletes/{id}", i -> new Object[]{i.athlete()}, i -> ATHLETE),
            patch("/api/athletes/{id}/active", i -> new Object[]{i.athlete()}, "value", "false"),
            write(HttpMethod.DELETE, "/api/athletes/{id}", i -> new Object[]{i.athlete()}, null),
            // Athlete analytics
            get("/api/athletes/{athleteId}/load", i -> new Object[]{i.athlete()}),
            get("/api/athletes/{athleteId}/signals", i -> new Object[]{i.athlete()}),
            get("/api/athletes/{athleteId}/development-coverage", i -> new Object[]{i.athlete()}),
            get("/api/athletes/{athleteId}/growth-velocity", i -> new Object[]{i.athlete()}),
            get("/api/athletes/{athleteId}/fitness-benchmarks", i -> new Object[]{i.athlete()}),
            get("/api/analytics/needs-attention", CrossClubSweepTest::none),
            // Assessments
            get("/api/athletes/{athleteId}/assessments", i -> new Object[]{i.athlete()}),
            write(HttpMethod.POST, "/api/athletes/{athleteId}/assessments", i -> new Object[]{i.athlete()}, i -> ASSESSMENT),
            get("/api/assessments/{id}", i -> new Object[]{i.assessment()}),
            write(HttpMethod.PUT, "/api/assessments/{id}", i -> new Object[]{i.assessment()}, i -> ASSESSMENT),
            write(HttpMethod.DELETE, "/api/assessments/{id}", i -> new Object[]{i.assessment()}, null),
            // Heights
            get("/api/athletes/{athleteId}/heights", i -> new Object[]{i.athlete()}),
            write(HttpMethod.POST, "/api/athletes/{athleteId}/heights", i -> new Object[]{i.athlete()}, i -> HEIGHT),
            get("/api/heights/{id}", i -> new Object[]{i.height()}),
            write(HttpMethod.PUT, "/api/heights/{id}", i -> new Object[]{i.height()}, i -> HEIGHT),
            write(HttpMethod.DELETE, "/api/heights/{id}", i -> new Object[]{i.height()}, null),
            // Fitness tests
            get("/api/athletes/{athleteId}/fitness-tests", i -> new Object[]{i.athlete()}),
            write(HttpMethod.POST, "/api/athletes/{athleteId}/fitness-tests", i -> new Object[]{i.athlete()}, i -> FITNESS),
            get("/api/fitness-tests/{id}", i -> new Object[]{i.fitnessTest()}),
            write(HttpMethod.PUT, "/api/fitness-tests/{id}", i -> new Object[]{i.fitnessTest()}, i -> FITNESS),
            write(HttpMethod.DELETE, "/api/fitness-tests/{id}", i -> new Object[]{i.fitnessTest()}, null),
            // Regatta results
            get("/api/athletes/{athleteId}/regatta-results", i -> new Object[]{i.athlete()}),
            write(HttpMethod.POST, "/api/athletes/{athleteId}/regatta-results", i -> new Object[]{i.athlete()}, i -> REGATTA),
            get("/api/regatta-results/{id}", i -> new Object[]{i.regatta()}),
            write(HttpMethod.PUT, "/api/regatta-results/{id}", i -> new Object[]{i.regatta()}, i -> REGATTA),
            write(HttpMethod.DELETE, "/api/regatta-results/{id}", i -> new Object[]{i.regatta()}, null),
            // KTC
            get("/api/athletes/{athleteId}/ktc", i -> new Object[]{i.athlete()}),
            write(HttpMethod.POST, "/api/athletes/{athleteId}/ktc", i -> new Object[]{i.athlete()}, i -> KTC),
            get("/api/ktc/{id}", i -> new Object[]{i.ktc()}),
            write(HttpMethod.PUT, "/api/ktc/{id}", i -> new Object[]{i.ktc()}, i -> KTC),
            write(HttpMethod.DELETE, "/api/ktc/{id}", i -> new Object[]{i.ktc()}, null),
            // Journal
            get("/api/athletes/{athleteId}/journal", i -> new Object[]{i.athlete()}),
            write(HttpMethod.POST, "/api/athletes/{athleteId}/journal", i -> new Object[]{i.athlete()}, i -> JOURNAL),
            get("/api/journal/{id}", i -> new Object[]{i.journal()}),
            write(HttpMethod.PUT, "/api/journal/{id}", i -> new Object[]{i.journal()}, i -> JOURNAL),
            write(HttpMethod.DELETE, "/api/journal/{id}", i -> new Object[]{i.journal()}, null),
            // Notes
            get("/api/athletes/{athleteId}/notes", i -> new Object[]{i.athlete()}),
            get("/api/sessions/{sessionId}/notes", i -> new Object[]{i.session()}),
            write(HttpMethod.POST, "/api/sessions/{sessionId}/notes", i -> new Object[]{i.session()}, CrossClubSweepTest::note),
            write(HttpMethod.PUT, "/api/notes/{id}", i -> new Object[]{i.note()}, i -> "{\"noteText\":\"Mine now\"}"),
            write(HttpMethod.DELETE, "/api/notes/{id}", i -> new Object[]{i.note()}, null),
            // Sessions
            get("/api/sessions", CrossClubSweepTest::none),
            get("/api/sessions/{id}", i -> new Object[]{i.session()}),
            write(HttpMethod.PUT, "/api/sessions/{id}", i -> new Object[]{i.session()}, i -> SESSION),
            patch("/api/sessions/{id}/status", i -> new Object[]{i.session()}, "value", "CANCELLED"),
            patch("/api/sessions/{id}/archive", i -> new Object[]{i.session()}, "value", "true"),
            write(HttpMethod.DELETE, "/api/sessions/{id}", i -> new Object[]{i.session()}, null),
            // Attendance
            get("/api/sessions/{sessionId}/attendance", i -> new Object[]{i.session()}),
            write(HttpMethod.PUT, "/api/sessions/{sessionId}/attendance", i -> new Object[]{i.session()}, CrossClubSweepTest::attendance),
            // Blocks
            get("/api/sessions/{sessionId}/blocks", i -> new Object[]{i.session()}),
            write(HttpMethod.POST, "/api/sessions/{sessionId}/blocks", i -> new Object[]{i.session()}, i -> BLOCK),
            get("/api/blocks/{id}", i -> new Object[]{i.block()}),
            write(HttpMethod.PUT, "/api/blocks/{id}", i -> new Object[]{i.block()}, i -> BLOCK),
            write(HttpMethod.DELETE, "/api/blocks/{id}", i -> new Object[]{i.block()}, null),
            // Performance
            get("/api/blocks/{blockId}/performance", i -> new Object[]{i.block()}),
            write(HttpMethod.PUT, "/api/blocks/{blockId}/performance", i -> new Object[]{i.block()}, CrossClubSweepTest::performance),
            write(HttpMethod.PUT, "/api/performance/{id}", i -> new Object[]{i.performance()},
                    i -> "{\"recordedTimeMs\":1,\"status\":\"COMPLETE\"}"),
            // Teams and members
            get("/api/teams", CrossClubSweepTest::none),
            get("/api/teams/{id}", i -> new Object[]{i.team()}),
            write(HttpMethod.PUT, "/api/teams/{id}", i -> new Object[]{i.team()}, i -> TEAM),
            patch("/api/teams/{id}/archive", i -> new Object[]{i.team()}, "value", "true"),
            write(HttpMethod.DELETE, "/api/teams/{id}", i -> new Object[]{i.team()}, null),
            get("/api/teams/{id}/members", i -> new Object[]{i.team()}),
            write(HttpMethod.POST, "/api/teams/{id}/members", i -> new Object[]{i.team()}, CrossClubSweepTest::member),
            write(HttpMethod.PUT, "/api/teams/{id}/members/{membershipId}",
                    i -> new Object[]{i.team(), i.membership()}, CrossClubSweepTest::member),
            write(HttpMethod.DELETE, "/api/teams/{id}/members/{membershipId}",
                    i -> new Object[]{i.team(), i.membership()}, null),
            get("/api/teams/{teamId}/load", i -> new Object[]{i.team()}),
            // Coaches (scoped by hand in CoachService, not by @TenantId)
            get("/api/coaches", CrossClubSweepTest::none),
            get("/api/coaches/pending", CrossClubSweepTest::none),
            get("/api/coaches/{id}", i -> new Object[]{i.coach()}),
            write(HttpMethod.PUT, "/api/coaches/{id}", i -> new Object[]{i.coach()}, i -> COACH),
            write(HttpMethod.DELETE, "/api/coaches/{id}", i -> new Object[]{i.coach()}, null));

    /**
     * Routes deliberately left out of {@link #SWEEP}. Most carry no club A id in the path, so the
     * sweep has nothing to aim at; each entry names where its isolation is proven instead. The
     * operator-only routes are cross-club by design (OperatorGuard), and every fixture coach is an
     * operator in tests, so sweeping them would only prove the operator can do its job.
     */
    private static final Map<String, String> EXEMPT = Map.of(
            "POST /api/auth/apple", "pre-auth sign-in; no tenant exists yet",
            "POST /api/clubs", "operator-only (OperatorGuard); creates a new club",
            "POST /api/coaches/{id}/approve", "operator-only (OperatorGuard); cross-club by design",
            "POST /api/clubs/join", "JoinFlowTest",
            "POST /api/athletes", "CreateByIdCollisionTest (body-supplied id collision)",
            "POST /api/sessions", "CreateByIdCollisionTest, RelationshipIsolationTest (foreign teamId)",
            "POST /api/teams", "CreateByIdCollisionTest",
            "POST /api/coaches", "CoachIsolationTest.clubBCannotHijackAClubACoachIdViaCreate");

    @Test
    void everyApiRouteIsSweptOrExplicitlyExempt() {
        Set<String> served = new TreeSet<>();
        mappings.getHandlerMethods().keySet().forEach(info ->
                info.getPatternValues().stream()
                        .filter(p -> p.startsWith("/api/"))
                        .forEach(p -> info.getMethodsCondition().getMethods()
                                .forEach(m -> served.add(m.name() + " " + p))));

        Set<String> accounted = new TreeSet<>(EXEMPT.keySet());
        SWEEP.forEach(r -> accounted.add(r.key()));

        Set<String> unaccounted = new TreeSet<>(served);
        unaccounted.removeAll(accounted);
        assertThat(unaccounted)
                .as("routes with no cross-club coverage — add each to SWEEP, or to EXEMPT with the reason it is safe")
                .isEmpty();

        Set<String> stale = new TreeSet<>(accounted);
        stale.removeAll(served);
        assertThat(stale).as("SWEEP/EXEMPT entries for routes the app no longer serves").isEmpty();
    }

    @Test
    void clubBCannotReachAnyOfClubAsRowsThroughAnyRoute() throws Exception {
        ClubFixture a = fixtures.club();
        ClubFixture b = fixtures.club();
        Ids ids = populate(a);

        // Positive control: club A really can see its rows, so club B's empty answers mean something.
        assertThat(call(a, get("/api/analytics/needs-attention", CrossClubSweepTest::none), ids)
                .getContentAsString()).contains(ids.athlete());

        Map<String, String> before = snapshot(a, ids);

        List<String> leaks = new ArrayList<>();
        for (Route r : SWEEP) {
            MockHttpServletResponse res = call(b, r, ids);
            int status = res.getStatus();
            if (r.isRead()) {
                String body = res.getContentAsString();
                if (status < 400 && ids.all().stream().anyMatch(body::contains)) {
                    leaks.add(r.key() + " -> " + status + " exposed a club A id: " + body);
                } else if (status >= 400 && status != 403 && status != 404) {
                    leaks.add(r.key() + " -> unexpected " + status + ": " + body);
                }
            } else if (status != 403 && status != 404) {
                leaks.add(r.key() + " -> " + status + " (expected 403/404): " + res.getContentAsString());
            }
        }
        assertThat(leaks).as("club B reached club A's data").isEmpty();

        assertThat(snapshot(a, ids)).as("club A's data after club B's attempts").isEqualTo(before);
    }

    private MockHttpServletResponse call(ClubFixture as, Route r, Ids ids) throws Exception {
        MockHttpServletRequestBuilder req = request(r.method(), r.template(), r.vars().apply(ids)).with(token(as));
        r.params().forEach(req::param);
        if (r.body() != null) {
            req.contentType(MediaType.APPLICATION_JSON).content(r.body().apply(ids));
        }
        return mvc.perform(req).andReturn().getResponse();
    }

    /** Club A's own answer to every read route, keyed by route. */
    private Map<String, String> snapshot(ClubFixture a, Ids ids) throws Exception {
        Map<String, String> out = new LinkedHashMap<>();
        for (Route r : SWEEP) {
            if (r.isRead()) {
                MockHttpServletResponse res = call(a, r, ids);
                out.put(r.key(), res.getStatus() + " " + res.getContentAsString());
            }
        }
        return out;
    }

    private RequestPostProcessor token(ClubFixture f) {
        return fixtures.token(f);
    }

    /** Club A with one of every tenant-scoped row, plus a declining trend so Needs-Attention flags the athlete. */
    private Ids populate(ClubFixture a) throws Exception {
        String athlete = create(a, "/api/athletes", ATHLETE);
        String team = create(a, "/api/teams", TEAM);
        String membership = create(a, "/api/teams/" + team + "/members", "{\"athleteId\":\"" + athlete + "\"}");

        // Three completed sessions of the same block, times worsening: the Needs-Attention trigger.
        String session = null;
        String block = null;
        String performance = null;
        int[] times = {50000, 60000, 70000};
        for (int n = 0; n < times.length; n++) {
            session = create(a, "/api/sessions", "{\"sessionName\":\"Practice\",\"scheduledDate\":\""
                    + LocalDate.now().minusDays((times.length - n) * 10L) + "\"}");
            mvc.perform(request(HttpMethod.PATCH, "/api/sessions/{id}/status", session)
                    .param("value", "COMPLETED").with(token(a)));
            block = create(a, "/api/sessions/" + session + "/blocks",
                    "{\"blockName\":\"Sprints\",\"blockType\":\"PADDLE_DISTANCE\",\"repetitionCount\":1}");
            String upserted = send(a, HttpMethod.PUT, "/api/blocks/" + block + "/performance",
                    "{\"entries\":[{\"athleteId\":\"" + athlete + "\",\"repNumber\":1,\"status\":\"COMPLETE\","
                            + "\"recordedTimeMs\":" + times[n] + "}]}");
            performance = JsonPath.read(upserted, "$[0].id");
        }
        send(a, HttpMethod.PUT, "/api/sessions/" + session + "/attendance",
                "{\"entries\":[{\"athleteId\":\"" + athlete + "\",\"status\":\"PRESENT\"}]}");

        return new Ids(
                a.coachId().toString(), athlete, team, membership, session, block,
                create(a, "/api/sessions/" + session + "/notes",
                        "{\"athleteId\":\"" + athlete + "\",\"noteText\":\"Strong catch\"}"),
                create(a, "/api/athletes/" + athlete + "/assessments", ASSESSMENT),
                create(a, "/api/athletes/" + athlete + "/heights", HEIGHT),
                create(a, "/api/athletes/" + athlete + "/fitness-tests", FITNESS),
                create(a, "/api/athletes/" + athlete + "/regatta-results", REGATTA),
                create(a, "/api/athletes/" + athlete + "/ktc", KTC),
                create(a, "/api/athletes/" + athlete + "/journal", JOURNAL),
                performance);
    }

    private String create(ClubFixture as, String path, String json) throws Exception {
        return JsonPath.read(send(as, HttpMethod.POST, path, json), "$.id");
    }

    private String send(ClubFixture as, HttpMethod method, String path, String json) throws Exception {
        MockHttpServletResponse res = mvc.perform(request(method, path).with(token(as))
                        .contentType(MediaType.APPLICATION_JSON).content(json))
                .andReturn().getResponse();
        assertThat(res.getStatus()).as(method + " " + path + ": " + res.getContentAsString()).isBetween(200, 299);
        return res.getContentAsString();
    }
}
