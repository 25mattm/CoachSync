package com.coachsync.web;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.FitnessTestResult;
import com.coachsync.domain.enums.Gender;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.FitnessTestResultRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.UUID;

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@WithMockUser
@Transactional
class FitnessBenchmarkControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private AthleteRepository athletes;
    @Autowired private FitnessTestResultRepository tests;

    private Athlete newAthlete(Gender gender) {
        Athlete a = new Athlete();
        a.setFirstName("Ada");
        a.setLastName("Paddle");
        a.setDateOfBirth(LocalDate.of(2012, 1, 1)); // age 14 in season 2026
        a.setGender(gender);
        return athletes.save(a);
    }

    private void test(Athlete a, String type, double result) {
        FitnessTestResult t = new FitnessTestResult();
        t.setAthlete(a);
        t.setTestType(type);
        t.setResult(result);
        t.setTestDate(LocalDate.of(2026, 6, 16));
        tests.save(t);
    }

    @Test
    void comparesBestResultAgainstBenchmark() throws Exception {
        Athlete a = newAthlete(Gender.FEMALE);
        test(a, "100m Sprint", 35.0);
        test(a, "100m Sprint", 33.0); // best = lowest
        test(a, "Pull-ups", 12.0);    // not benchmarked -> excluded

        mvc.perform(get("/api/athletes/{id}/fitness-benchmarks", a.getId()).param("year", "2026"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].testType", is("100m Sprint")))
                .andExpect(jsonPath("$[0].bestResultSeconds", is(33.0)))
                .andExpect(jsonPath("$[0].benchmarkSeconds", is(31.5))) // F14 100m
                .andExpect(jsonPath("$[0].percentOfBenchmark", is(104.8))); // 33 / 31.5 * 100
    }

    @Test
    void emptyWithoutGender() throws Exception {
        Athlete a = newAthlete(null);
        test(a, "100m Sprint", 33.0);
        mvc.perform(get("/api/athletes/{id}/fitness-benchmarks", a.getId()).param("year", "2026"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(0)));
    }

    @Test
    void unknownAthleteReturns404() throws Exception {
        mvc.perform(get("/api/athletes/{id}/fitness-benchmarks", UUID.randomUUID()))
                .andExpect(status().isNotFound());
    }
}
