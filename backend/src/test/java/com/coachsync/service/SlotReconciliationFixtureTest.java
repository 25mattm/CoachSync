package com.coachsync.service;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.PerformanceRecord;
import com.coachsync.domain.SessionBlock;
import com.coachsync.domain.enums.BlockType;
import com.coachsync.domain.enums.RepEntryStatus;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.TestFactory;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.UUID;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * Runs {@code shared/fixtures/slot-reconciliation.json} — the same cases the iOS
 * {@code SlotReconciliationTests.testSharedFixtureCases} run — through
 * {@link SlotGenerationService#planBlock}, so the backend port and the app can't drift apart.
 */
class SlotReconciliationFixtureTest {

    private static final Path FIXTURE = Path.of("..", "shared", "fixtures", "slot-reconciliation.json");

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
        SessionBlock block = new SessionBlock();
        block.setId(UUID.randomUUID());
        block.setBlockName("Block");
        // The fixture uses the iOS display strings ("Paddle Distance").
        block.setBlockType(BlockType.valueOf(c.get("blockType").asString().toUpperCase().replace(' ', '_')));
        block.setRepetitionCount(c.get("repetitionCount").asInt());

        Map<String, Athlete> athletes = new HashMap<>();
        List<Athlete> present = new ArrayList<>();
        Set<UUID> presentIds = new HashSet<>();
        for (JsonNode name : c.get("present")) {
            Athlete athlete = athlete(athletes, name.asString());
            present.add(athlete);
            presentIds.add(athlete.getId());
        }

        List<PerformanceRecord> existing = new ArrayList<>();
        for (JsonNode s : c.get("existing")) {
            PerformanceRecord r = new PerformanceRecord();
            r.setId(UUID.randomUUID());
            r.setSessionBlock(block);
            r.setAthlete(athlete(athletes, s.get("athlete").asString()));
            r.setRepNumber(s.get("rep").asInt());
            switch (s.get("state").asString()) {
                case "pending" -> r.setStatus(RepEntryStatus.PENDING);
                case "time" -> {
                    r.setStatus(RepEntryStatus.COMPLETE);
                    r.setRecordedTimeMs(120_000);
                }
                case "dns" -> r.setStatus(RepEntryStatus.DNS);
                case "dnf" -> r.setStatus(RepEntryStatus.DNF);
                default -> throw new IllegalArgumentException("Unknown slot state " + s.get("state"));
            }
            existing.add(r);
        }

        SlotGenerationService.SlotPlan plan = SlotGenerationService.planBlock(block, present, presentIds, existing);

        List<PerformanceRecord> remaining = new ArrayList<>(existing);
        remaining.removeAll(plan.toDelete());
        remaining.addAll(plan.toInsert());
        Map<UUID, String> names = new HashMap<>();
        athletes.forEach((name, a) -> names.put(a.getId(), name));
        Set<String> actual = new TreeSet<>();
        for (PerformanceRecord r : remaining) {
            actual.add(names.get(r.getAthlete().getId()) + "#" + r.getRepNumber());
        }

        Set<String> expected = new TreeSet<>();
        c.get("expected").get("slots").forEach(slot -> expected.add(slot.asString()));
        assertEquals(expected, actual, "slots");
        assertEquals(c.get("expected").get("changes").asInt(),
                plan.toDelete().size() + plan.toInsert().size(), "changes");
    }

    private static Athlete athlete(Map<String, Athlete> athletes, String name) {
        return athletes.computeIfAbsent(name, n -> {
            Athlete a = new Athlete();
            a.setId(UUID.randomUUID());
            a.setFirstName(n);
            return a;
        });
    }
}
