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
class RegattaResultControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private AthleteRepository athletes;

    private Athlete newAthlete() {
        Athlete a = new Athlete();
        a.setFirstName("Ada");
        a.setLastName("Paddle");
        a.setDateOfBirth(LocalDate.of(2012, 1, 1));
        return athletes.save(a);
    }

    private static final String VALID =
            "{\"regattaName\":\"Nationals\",\"location\":\"Welland\",\"regattaDate\":\"2026-07-01\","
                    + "\"eventDistanceMetres\":500,\"placement\":2,\"totalCompetitors\":12,\"resultTimeMs\":120500}";

    private String createResult(UUID athleteId, String json) throws Exception {
        String body = mvc.perform(post("/api/athletes/{id}/regatta-results", athleteId)
                        .contentType(MediaType.APPLICATION_JSON).content(json))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", containsString("/api/regatta-results/")))
                .andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.id");
    }

    @Test
    void createsAndGetsResult() throws Exception {
        Athlete a = newAthlete();
        String id = createResult(a.getId(), VALID);
        mvc.perform(get("/api/regatta-results/{id}", id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.regattaName", is("Nationals")))
                .andExpect(jsonPath("$.placement", is(2)))
                .andExpect(jsonPath("$.resultTimeMs", is(120500)));
    }

    @Test
    void blankNameReturns400() throws Exception {
        Athlete a = newAthlete();
        mvc.perform(post("/api/athletes/{id}/regatta-results", a.getId()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"regattaName\":\"\",\"regattaDate\":\"2026-07-01\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void negativePlacementReturns400() throws Exception {
        Athlete a = newAthlete();
        mvc.perform(post("/api/athletes/{id}/regatta-results", a.getId()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"regattaName\":\"X\",\"regattaDate\":\"2026-07-01\",\"placement\":-1}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void updatesResult() throws Exception {
        Athlete a = newAthlete();
        String id = createResult(a.getId(), VALID);
        mvc.perform(put("/api/regatta-results/{id}", id).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"regattaName\":\"Provincials\",\"regattaDate\":\"2026-08-01\","
                                + "\"eventDistanceMetres\":1000,\"resultTimeMs\":260000}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.regattaName", is("Provincials")))
                .andExpect(jsonPath("$.placement").isEmpty());
    }

    @Test
    void deletesResult() throws Exception {
        Athlete a = newAthlete();
        String id = createResult(a.getId(), VALID);
        mvc.perform(delete("/api/regatta-results/{id}", id)).andExpect(status().isNoContent());
        mvc.perform(get("/api/regatta-results/{id}", id)).andExpect(status().isNotFound());
    }

    @Test
    void athleteWithResultCannotBeDeleted() throws Exception {
        Athlete a = newAthlete();
        createResult(a.getId(), VALID);
        mvc.perform(delete("/api/athletes/{id}", a.getId())).andExpect(status().isConflict());
    }

    @Test
    void createForUnknownAthleteReturns404() throws Exception {
        mvc.perform(post("/api/athletes/{id}/regatta-results", UUID.randomUUID())
                        .contentType(MediaType.APPLICATION_JSON).content(VALID))
                .andExpect(status().isNotFound());
    }
}
