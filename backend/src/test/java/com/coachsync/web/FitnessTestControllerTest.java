package com.coachsync.web;

import com.coachsync.domain.Athlete;
import com.coachsync.repository.AthleteRepository;
import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.UUID;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.is;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@WithMockUser
@Transactional
class FitnessTestControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private AthleteRepository athletes;

    private Athlete newAthlete() {
        Athlete a = new Athlete();
        a.setFirstName("Ada");
        a.setLastName("Paddle");
        a.setDateOfBirth(LocalDate.of(2012, 1, 1));
        return athletes.save(a);
    }

    private String createTest(UUID athleteId, String json) throws Exception {
        String body = mvc.perform(post("/api/athletes/{id}/fitness-tests", athleteId)
                        .contentType(MediaType.APPLICATION_JSON).content(json))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", containsString("/api/fitness-tests/")))
                .andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.id");
    }

    @Test
    void createsAndGetsTest() throws Exception {
        Athlete a = newAthlete();
        String id = createTest(a.getId(),
                "{\"testType\":\"2km erg\",\"result\":480.5,\"unit\":\"seconds\",\"testDate\":\"2026-06-16\"}");
        mvc.perform(get("/api/fitness-tests/{id}", id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.testType", is("2km erg")))
                .andExpect(jsonPath("$.result", is(480.5)))
                .andExpect(jsonPath("$.unit", is("seconds")));
    }

    @Test
    void unitDefaultsToSecondsWhenOmitted() throws Exception {
        Athlete a = newAthlete();
        String id = createTest(a.getId(),
                "{\"testType\":\"Pull-ups\",\"result\":12,\"testDate\":\"2026-06-16\"}");
        mvc.perform(get("/api/fitness-tests/{id}", id))
                .andExpect(jsonPath("$.unit", is("seconds")));
    }

    @Test
    void blankTestTypeReturns400() throws Exception {
        Athlete a = newAthlete();
        mvc.perform(post("/api/athletes/{id}/fitness-tests", a.getId()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"testType\":\"\",\"result\":1,\"testDate\":\"2026-06-16\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void updatesTest() throws Exception {
        Athlete a = newAthlete();
        String id = createTest(a.getId(),
                "{\"testType\":\"2km erg\",\"result\":480.5,\"testDate\":\"2026-06-16\"}");
        mvc.perform(put("/api/fitness-tests/{id}", id).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"testType\":\"2km erg\",\"result\":465.0,\"unit\":\"seconds\",\"testDate\":\"2026-07-16\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.result", is(465.0)));
    }

    @Test
    void deletesTest() throws Exception {
        Athlete a = newAthlete();
        String id = createTest(a.getId(),
                "{\"testType\":\"2km erg\",\"result\":480.5,\"testDate\":\"2026-06-16\"}");
        mvc.perform(delete("/api/fitness-tests/{id}", id)).andExpect(status().isNoContent());
        mvc.perform(get("/api/fitness-tests/{id}", id)).andExpect(status().isNotFound());
    }

    @Test
    void athleteWithTestCannotBeDeleted() throws Exception {
        Athlete a = newAthlete();
        createTest(a.getId(), "{\"testType\":\"2km erg\",\"result\":480.5,\"testDate\":\"2026-06-16\"}");
        mvc.perform(delete("/api/athletes/{id}", a.getId())).andExpect(status().isConflict());
    }

    @Test
    void createForUnknownAthleteReturns404() throws Exception {
        mvc.perform(post("/api/athletes/{id}/fitness-tests", UUID.randomUUID())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"testType\":\"2km erg\",\"result\":480.5,\"testDate\":\"2026-06-16\"}"))
                .andExpect(status().isNotFound());
    }
}
