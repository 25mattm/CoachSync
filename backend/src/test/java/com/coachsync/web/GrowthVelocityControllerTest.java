package com.coachsync.web;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.HeightRecord;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.HeightRecordRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.UUID;

import static org.hamcrest.Matchers.is;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@WithMockUser
@Transactional
class GrowthVelocityControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private AthleteRepository athletes;
    @Autowired private HeightRecordRepository heights;

    private Athlete newAthlete() {
        Athlete a = new Athlete();
        a.setFirstName("Ada");
        a.setLastName("Paddle");
        a.setDateOfBirth(LocalDate.of(2012, 1, 1));
        return athletes.save(a);
    }

    private void height(Athlete a, LocalDate date, double cm) {
        HeightRecord h = new HeightRecord();
        h.setAthlete(a);
        h.setDate(date);
        h.setHeightCm(cm);
        heights.save(h);
    }

    @Test
    void flagsPhvForRapidGrowth() throws Exception {
        Athlete a = newAthlete();
        height(a, LocalDate.of(2024, 6, 16), 150.0);
        height(a, LocalDate.of(2025, 6, 16), 156.0); // +6 cm over ~1 year

        mvc.perform(get("/api/athletes/{id}/growth-velocity", a.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.growthVelocityCmPerYear", is(6.0)))
                .andExpect(jsonPath("$.phv", is(true)));
    }

    @Test
    void noPhvForModerateGrowth() throws Exception {
        Athlete a = newAthlete();
        height(a, LocalDate.of(2024, 6, 16), 150.0);
        height(a, LocalDate.of(2025, 6, 16), 153.0); // +3 cm over ~1 year

        mvc.perform(get("/api/athletes/{id}/growth-velocity", a.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.growthVelocityCmPerYear", is(3.0)))
                .andExpect(jsonPath("$.phv", is(false)));
    }

    @Test
    void nullVelocityWithASingleReading() throws Exception {
        Athlete a = newAthlete();
        height(a, LocalDate.of(2025, 6, 16), 150.0);

        mvc.perform(get("/api/athletes/{id}/growth-velocity", a.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.growthVelocityCmPerYear").isEmpty())
                .andExpect(jsonPath("$.phv", is(false)));
    }

    @Test
    void unknownAthleteReturns404() throws Exception {
        mvc.perform(get("/api/athletes/{id}/growth-velocity", UUID.randomUUID()))
                .andExpect(status().isNotFound());
    }
}
