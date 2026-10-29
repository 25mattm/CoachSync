package com.coachsync.web.dto;

import jakarta.validation.Validation;
import jakarta.validation.Validator;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.TestFactory;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * Runs {@code shared/fixtures/guardian-emails.json} — the same addresses the iOS
 * {@code EmailValidationTests} check against {@code String.isPlausibleEmail} — through the
 * constraints on {@link AthleteRequest#guardianEmail()}, so the app never accepts an address
 * every sync push would then refuse.
 */
class GuardianEmailFixtureTest {

    private static final Path FIXTURE = Path.of("..", "shared", "fixtures", "guardian-emails.json");

    private final Validator validator = Validation.buildDefaultValidatorFactory().getValidator();

    @TestFactory
    Stream<DynamicTest> sharedFixtureCases() {
        JsonNode fixture = new ObjectMapper().readTree(FIXTURE.toFile());
        List<DynamicTest> tests = new ArrayList<>();
        for (JsonNode email : fixture.get("valid")) {
            tests.add(DynamicTest.dynamicTest("accepts " + email.asString(), () -> check(email.asString(), true)));
        }
        for (JsonNode email : fixture.get("invalid")) {
            tests.add(DynamicTest.dynamicTest("rejects " + email.asString(), () -> check(email.asString(), false)));
        }
        return tests.stream();
    }

    private void check(String email, boolean valid) {
        boolean accepted = validator.validateValue(AthleteRequest.class, "guardianEmail", email).isEmpty();
        assertEquals(valid, accepted, email);
    }
}
