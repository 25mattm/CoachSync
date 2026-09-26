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
class KtcControllerTest {

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
            "{\"date\":\"2026-06-16\",\"window\":\"Pre-Competition\",\"setupRecoveryScore\":4,"
                    + "\"catchScore\":3,\"propulsionDrawScore\":2,\"exitScore\":5,\"notes\":\"solid\"}";

    private String createKtc(UUID athleteId, String json) throws Exception {
        String body = mvc.perform(post("/api/athletes/{id}/ktc", athleteId)
                        .contentType(MediaType.APPLICATION_JSON).content(json))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", containsString("/api/ktc/")))
                .andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.id");
    }

    @Test
    void createsKtcAndComputesAverage() throws Exception {
        Athlete a = newAthlete();
        String id = createKtc(a.getId(), VALID);
        mvc.perform(get("/api/ktc/{id}", id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.window", is("Pre-Competition")))
                .andExpect(jsonPath("$.averageScore", is(3.5))); // (4+3+2+5)/4
    }

    @Test
    void scoreOutOfRangeReturns400() throws Exception {
        Athlete a = newAthlete();
        mvc.perform(post("/api/athletes/{id}/ktc", a.getId()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"date\":\"2026-06-16\",\"window\":\"X\",\"setupRecoveryScore\":9,"
                                + "\"catchScore\":3,\"propulsionDrawScore\":2,\"exitScore\":5}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void blankWindowReturns400() throws Exception {
        Athlete a = newAthlete();
        mvc.perform(post("/api/athletes/{id}/ktc", a.getId()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"date\":\"2026-06-16\",\"window\":\"\",\"setupRecoveryScore\":4,"
                                + "\"catchScore\":3,\"propulsionDrawScore\":2,\"exitScore\":5}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void updatesKtc() throws Exception {
        Athlete a = newAthlete();
        String id = createKtc(a.getId(), VALID);
        mvc.perform(put("/api/ktc/{id}", id).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"date\":\"2026-06-16\",\"window\":\"Specific Prep\",\"setupRecoveryScore\":5,"
                                + "\"catchScore\":5,\"propulsionDrawScore\":5,\"exitScore\":5}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.window", is("Specific Prep")))
                .andExpect(jsonPath("$.averageScore", is(5.0)));
    }

    @Test
    void deletesKtc() throws Exception {
        Athlete a = newAthlete();
        String id = createKtc(a.getId(), VALID);
        mvc.perform(delete("/api/ktc/{id}", id)).andExpect(status().isNoContent());
        mvc.perform(get("/api/ktc/{id}", id)).andExpect(status().isNotFound());
    }

    @Test
    void athleteWithKtcCannotBeDeleted() throws Exception {
        Athlete a = newAthlete();
        createKtc(a.getId(), VALID);
        mvc.perform(delete("/api/athletes/{id}", a.getId())).andExpect(status().isConflict());
    }

    @Test
    void createForUnknownAthleteReturns404() throws Exception {
        mvc.perform(post("/api/athletes/{id}/ktc", UUID.randomUUID())
                        .contentType(MediaType.APPLICATION_JSON).content(VALID))
                .andExpect(status().isNotFound());
    }
}
