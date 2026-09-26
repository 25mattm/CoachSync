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
import static org.hamcrest.Matchers.hasSize;
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
class AssessmentControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private AthleteRepository athletes;

    private Athlete newAthlete() {
        Athlete a = new Athlete();
        a.setFirstName("Ada");
        a.setLastName("Paddle");
        a.setDateOfBirth(LocalDate.of(2012, 1, 1));
        return athletes.save(a);
    }

    private String createAssessment(UUID athleteId, String json) throws Exception {
        String body = mvc.perform(post("/api/athletes/{id}/assessments", athleteId)
                        .contentType(MediaType.APPLICATION_JSON).content(json))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", containsString("/api/assessments/")))
                .andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.id");
    }

    @Test
    void createsAssessmentWithRatingsAndComputesAverage() throws Exception {
        Athlete a = newAthlete();
        String id = createAssessment(a.getId(),
                "{\"date\":\"2026-06-16\",\"stage\":\"ACQUISITION\",\"overallNotes\":\"Good\","
                        + "\"ratings\":[{\"category\":\"Balance\",\"factor\":\"Posture\",\"score\":4},"
                        + "{\"category\":\"Catch\",\"factor\":\"Timing\",\"score\":2}]}");

        mvc.perform(get("/api/assessments/{id}", id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.stage", is("ACQUISITION")))
                .andExpect(jsonPath("$.averageScore", is(3.0)))
                .andExpect(jsonPath("$.ratings", hasSize(2)));
    }

    @Test
    void scoreOutOfRangeReturns400() throws Exception {
        Athlete a = newAthlete();
        mvc.perform(post("/api/athletes/{id}/assessments", a.getId())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"date\":\"2026-06-16\",\"ratings\":[{\"category\":\"X\",\"factor\":\"Y\",\"score\":6}]}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void updateFullyReplacesRatings() throws Exception {
        Athlete a = newAthlete();
        String id = createAssessment(a.getId(),
                "{\"date\":\"2026-06-16\",\"ratings\":[{\"category\":\"Balance\",\"factor\":\"Posture\",\"score\":4},"
                        + "{\"category\":\"Catch\",\"factor\":\"Timing\",\"score\":2}]}");

        mvc.perform(put("/api/assessments/{id}", id).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"date\":\"2026-06-16\",\"ratings\":[{\"category\":\"Exit\",\"factor\":\"Clean\",\"score\":5}]}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.ratings", hasSize(1)))
                .andExpect(jsonPath("$.ratings[0].factor", is("Clean")))
                .andExpect(jsonPath("$.averageScore", is(5.0)));
    }

    @Test
    void deletesAssessment() throws Exception {
        Athlete a = newAthlete();
        String id = createAssessment(a.getId(), "{\"date\":\"2026-06-16\",\"ratings\":[]}");
        mvc.perform(delete("/api/assessments/{id}", id)).andExpect(status().isNoContent());
        mvc.perform(get("/api/assessments/{id}", id)).andExpect(status().isNotFound());
    }

    @Test
    void athleteWithAssessmentCannotBeDeleted() throws Exception {
        Athlete a = newAthlete();
        createAssessment(a.getId(), "{\"date\":\"2026-06-16\",\"ratings\":[]}");
        // The assessment is recorded history -> the athlete delete guard refuses (409).
        mvc.perform(delete("/api/athletes/{id}", a.getId())).andExpect(status().isConflict());
    }

    @Test
    void createForUnknownAthleteReturns404() throws Exception {
        mvc.perform(post("/api/athletes/{id}/assessments", UUID.randomUUID())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"date\":\"2026-06-16\",\"ratings\":[]}"))
                .andExpect(status().isNotFound());
    }
}
