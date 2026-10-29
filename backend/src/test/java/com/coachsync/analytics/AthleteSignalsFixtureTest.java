package com.coachsync.analytics;

import com.coachsync.domain.CoachSession;
import com.coachsync.domain.PerformanceRecord;
import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.enums.BlockType;
import com.coachsync.domain.enums.RepEntryStatus;
import com.coachsync.web.dto.AthleteSignalsResponse;
import com.coachsync.web.dto.InconsistentPacing;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.TestFactory;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

import java.nio.file.Path;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * Runs {@code shared/fixtures/athlete-signals.json} — the same cases the iOS
 * {@code InsightSignalsTests.testSharedFixtureCases} run — through {@link AthleteSignalsService#signalsFrom},
 * so the backend port and the app can't drift apart.
 */
class AthleteSignalsFixtureTest {

    private static final Path FIXTURE = Path.of("..", "shared", "fixtures", "athlete-signals.json");
    private static final LocalDate BASE = LocalDate.of(2026, 1, 1);

    private final AthleteSignalsService service = new AthleteSignalsService(null, null, null);

    @TestFactory
    Stream<DynamicTest> sharedFixtureCases() {
        JsonNode cases = new ObjectMapper().readTree(FIXTURE.toFile()).get("cases");
        List<DynamicTest> tests = new ArrayList<>();
        for (JsonNode c : cases) {
            tests.add(DynamicTest.dynamicTest(c.get("name").asString(), () -> check(c)));
        }
        return tests.stream();
    }

    private void check(JsonNode c) {
        List<PerformanceRecord> records = new ArrayList<>();
        for (JsonNode s : c.get("sessions")) {
            CoachSession session = new CoachSession();
            session.setId(UUID.randomUUID());
            session.setSessionName("Practice");
            session.setScheduledDate(BASE.plusDays(s.get("day").asInt()));
            SessionBlock block = new SessionBlock();
            block.setId(UUID.randomUUID());
            block.setSession(session);
            block.setBlockName(s.get("block").asString());
            block.setBlockType(BlockType.PADDLE_DISTANCE);
            int repNumber = 1;
            for (JsonNode time : s.get("reps")) {
                PerformanceRecord r = new PerformanceRecord();
                r.setId(UUID.randomUUID());
                r.setSessionBlock(block);
                r.setRepNumber(repNumber++);
                r.setStatus(RepEntryStatus.COMPLETE);
                r.setRecordedTimeMs(time.asInt());
                records.add(r);
            }
        }

        AthleteSignalsResponse actual = service.signalsFrom(UUID.randomUUID(), records);
        JsonNode expected = c.get("expected");
        assertEquals(textOrNull(expected.get("decliningBlock")), actual.decliningBlock(), "decliningBlock");
        assertEquals(textOrNull(expected.get("mostImprovedBlock")), actual.mostImprovedBlock(), "mostImprovedBlock");
        JsonNode pacing = expected.get("inconsistentPacing");
        InconsistentPacing expectedPacing = pacing == null || pacing.isNull()
                ? null
                : new InconsistentPacing(pacing.get("blockName").asString(), pacing.get("cvPercent").asInt());
        assertEquals(expectedPacing, actual.inconsistentPacing(), "inconsistentPacing");
    }

    private static String textOrNull(JsonNode node) {
        return node == null || node.isNull() ? null : node.asString();
    }
}
