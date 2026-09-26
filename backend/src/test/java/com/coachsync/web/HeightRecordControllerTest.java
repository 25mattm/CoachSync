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
class HeightRecordControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private AthleteRepository athletes;

    private Athlete newAthlete() {
        Athlete a = new Athlete();
        a.setFirstName("Ada");
        a.setLastName("Paddle");
        a.setDateOfBirth(LocalDate.of(2012, 1, 1));
        return athletes.save(a);
    }

    private String createHeight(UUID athleteId, String json) throws Exception {
        String body = mvc.perform(post("/api/athletes/{id}/heights", athleteId)
                        .contentType(MediaType.APPLICATION_JSON).content(json))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", containsString("/api/heights/")))
                .andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.id");
    }

    @Test
    void createsAndGetsHeight() throws Exception {
        Athlete a = newAthlete();
        String id = createHeight(a.getId(), "{\"heightCm\":162.5,\"date\":\"2026-06-16\"}");
        mvc.perform(get("/api/heights/{id}", id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.heightCm", is(162.5)));
    }

    @Test
    void nonPositiveHeightReturns400() throws Exception {
        Athlete a = newAthlete();
        mvc.perform(post("/api/athletes/{id}/heights", a.getId()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"heightCm\":0,\"date\":\"2026-06-16\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void updatesHeight() throws Exception {
        Athlete a = newAthlete();
        String id = createHeight(a.getId(), "{\"heightCm\":162.5,\"date\":\"2026-06-16\"}");
        mvc.perform(put("/api/heights/{id}", id).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"heightCm\":165.0,\"date\":\"2026-09-16\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.heightCm", is(165.0)));
    }

    @Test
    void deletesHeight() throws Exception {
        Athlete a = newAthlete();
        String id = createHeight(a.getId(), "{\"heightCm\":162.5,\"date\":\"2026-06-16\"}");
        mvc.perform(delete("/api/heights/{id}", id)).andExpect(status().isNoContent());
        mvc.perform(get("/api/heights/{id}", id)).andExpect(status().isNotFound());
    }

    @Test
    void athleteWithHeightCannotBeDeleted() throws Exception {
        Athlete a = newAthlete();
        createHeight(a.getId(), "{\"heightCm\":162.5,\"date\":\"2026-06-16\"}");
        mvc.perform(delete("/api/athletes/{id}", a.getId())).andExpect(status().isConflict());
    }

    @Test
    void createForUnknownAthleteReturns404() throws Exception {
        mvc.perform(post("/api/athletes/{id}/heights", UUID.randomUUID())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"heightCm\":162.5,\"date\":\"2026-06-16\"}"))
                .andExpect(status().isNotFound());
    }
}
