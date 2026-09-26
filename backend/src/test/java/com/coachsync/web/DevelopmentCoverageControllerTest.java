package com.coachsync.web;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.DevelopmentNote;
import com.coachsync.domain.TechnicalAssessment;
import com.coachsync.domain.TechnicalRating;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.DevelopmentNoteRepository;
import com.coachsync.repository.TechnicalAssessmentRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.List;
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
class DevelopmentCoverageControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private AthleteRepository athletes;
    @Autowired private TechnicalAssessmentRepository assessments;
    @Autowired private DevelopmentNoteRepository journal;

    private Athlete newAthlete() {
        Athlete a = new Athlete();
        a.setFirstName("Ada");
        a.setLastName("Paddle");
        a.setDateOfBirth(LocalDate.of(2012, 1, 1));
        return athletes.save(a);
    }

    private void addRating(TechnicalAssessment a, String category, String factor, int score) {
        TechnicalRating r = new TechnicalRating();
        r.setAssessment(a);
        r.setCategory(category);
        r.setFactor(factor);
        r.setScore(score);
        a.getRatings().add(r);
    }

    private void journalNote(Athlete a, LocalDate date, String tag) {
        DevelopmentNote n = new DevelopmentNote();
        n.setAthlete(a);
        n.setDate(date);
        n.setText("note");
        n.setTags(List.of(tag));
        journal.save(n);
    }

    @Test
    void reportsCoverageForFocusAreas() throws Exception {
        Athlete a = newAthlete();
        TechnicalAssessment assessment = new TechnicalAssessment();
        assessment.setAthlete(a);
        assessment.setDate(LocalDate.now());
        addRating(assessment, "Balance", "Posture", 2);       // focus area (<= 2)
        addRating(assessment, "Catch", "Timing", 4);          // not a focus area
        addRating(assessment, "Exit", "Clean finish", 1);     // focus area
        assessments.save(assessment);

        journalNote(a, LocalDate.now(), "Posture");                  // covers Balance/Posture
        journalNote(a, LocalDate.now().minusDays(90), "Clean");      // would cover Exit, but out of window

        mvc.perform(get("/api/athletes/{id}/development-coverage", a.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)))                // only the two focus areas, by category
                .andExpect(jsonPath("$[0].category", is("Balance")))
                .andExpect(jsonPath("$[0].factor", is("Posture")))
                .andExpect(jsonPath("$[0].noteCount", is(1)))
                .andExpect(jsonPath("$[0].covered", is(true)))
                .andExpect(jsonPath("$[1].category", is("Exit")))
                .andExpect(jsonPath("$[1].noteCount", is(0)))         // 90-day-old note excluded
                .andExpect(jsonPath("$[1].covered", is(false)));
    }

    @Test
    void emptyWhenNoAssessment() throws Exception {
        Athlete a = newAthlete();
        mvc.perform(get("/api/athletes/{id}/development-coverage", a.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(0)));
    }

    @Test
    void unknownAthleteReturns404() throws Exception {
        mvc.perform(get("/api/athletes/{id}/development-coverage", UUID.randomUUID()))
                .andExpect(status().isNotFound());
    }
}
