package com.coachsync.web;

import com.coachsync.domain.Club;
import com.coachsync.domain.Coach;
import com.coachsync.repository.ClubRepository;
import com.coachsync.repository.CoachRepository;
import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.UUID;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.is;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Coach CRUD, now club-scoped. Deliberately <b>not</b> {@code @Transactional}: creating a
 * {@code CoachSession} (tenant-scoped) for the delete-guard test must land in this test's club, but
 * Hibernate fixes a transaction's tenant when its session first opens — so a class-level test
 * transaction would pin every write to the tenant in force at the first DB touch, not the tenant of
 * each request's JWT. Each test instead uses a fresh club id and authenticates with a matching
 * {@code club} claim; rows from a sibling test belong to another club and are simply invisible.
 */
@SpringBootTest
@AutoConfigureMockMvc
class CoachControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private CoachRepository coaches;
    @Autowired private ClubRepository clubs;

    private UUID clubId;
    private UUID actingCoachId;

    @BeforeEach
    void seedClubAndActingCoach() {
        Club club = new Club();
        club.setName("Test Club");
        clubId = clubs.save(club).getId();
        actingCoachId = saveCoach("Pat", club);
    }

    /** Coach is un-tenanted, so a direct save with an explicit club works from any request context. */
    private UUID saveCoach(String name, Club club) {
        Coach coach = new Coach();
        coach.setName(name);
        coach.setEmail("pat@example.com");   // matches coachsync.auth.allowed-emails in test props
        coach.setAppleUserId("apple-" + UUID.randomUUID());
        coach.setClub(club);
        return coaches.save(coach).getId();
    }

    /** A token for the acting coach, approved into this test's club. */
    private RequestPostProcessor auth() {
        return jwt().jwt(j -> j.subject(actingCoachId.toString()).claim("club", clubId.toString()));
    }

    private String createCoach(String name) throws Exception {
        String body = mvc.perform(post("/api/coaches").with(auth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"" + name + "\",\"role\":\"Head\"}"))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", containsString("/api/coaches/")))
                .andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.id");
    }

    @Test
    void createsReadsUpdatesCoach() throws Exception {
        String id = createCoach("Assistant");
        mvc.perform(get("/api/coaches/{id}", id).with(auth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name", is("Assistant")))
                .andExpect(jsonPath("$.role", is("Head")));
        mvc.perform(put("/api/coaches/{id}", id).with(auth()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Assistant Coach\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name", is("Assistant Coach")));
    }

    @Test
    void blankNameReturns400() throws Exception {
        mvc.perform(post("/api/coaches").with(auth()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors.name").exists());
    }

    @Test
    void deletesUnreferencedCoach() throws Exception {
        String id = createCoach("Temp");
        mvc.perform(delete("/api/coaches/{id}", id).with(auth())).andExpect(status().isNoContent());
        mvc.perform(get("/api/coaches/{id}", id).with(auth())).andExpect(status().isNotFound());
    }

    @Test
    void aClubmateCannotDeleteAnotherCoachsSignedInAccount() throws Exception {
        UUID clubmateId = saveCoach("Clubmate", clubs.findById(clubId).orElseThrow());
        mvc.perform(delete("/api/coaches/{id}", clubmateId).with(auth())).andExpect(status().isConflict());
        mvc.perform(get("/api/coaches/{id}", clubmateId).with(auth())).andExpect(status().isOk());
    }

    @Test
    void aCoachMayDeleteTheirOwnSignedInAccount() throws Exception {
        mvc.perform(delete("/api/coaches/{id}", actingCoachId).with(auth())).andExpect(status().isNoContent());
        assertEquals(false, coaches.existsById(actingCoachId));
    }

    @Test
    void rePostWithExistingIdPreservesServerOwnedFields() throws Exception {
        // appleUserId/email/createdAt are server-owned — they never appear in CoachRequest. A coach
        // linked to an Apple ID has them set; a re-sent sync insert (POST-with-id) for the same row must
        // update only the request fields and leave the auth link + createdAt intact.
        Club club = clubs.findById(clubId).orElseThrow();
        Coach coach = new Coach();
        coach.setName("Linked");
        coach.setAppleUserId("apple-sub-xyz");
        coach.setEmail("coach@example.com");
        coach.setClub(club);
        coach = coaches.save(coach);
        UUID id = coach.getId();
        Instant originalCreatedAt = coach.getCreatedAt();

        mvc.perform(post("/api/coaches").with(auth()).contentType(MediaType.APPLICATION_JSON).content("""
                {"id":"%s","name":"Renamed","updatedAt":"2030-01-01T00:00:00Z"}
                """.formatted(id)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.name", is("Renamed")));

        Coach reloaded = coaches.findById(id).orElseThrow();
        assertEquals("apple-sub-xyz", reloaded.getAppleUserId(), "Apple link must survive a re-POST");
        assertEquals("coach@example.com", reloaded.getEmail(), "email must survive a re-POST");
        // Compared at the column's microsecond precision: on Linux, Instant.now() carries
        // nanoseconds that the stored value has already dropped, which isn't a reset.
        assertEquals(originalCreatedAt.truncatedTo(ChronoUnit.MICROS),
                reloaded.getCreatedAt().truncatedTo(ChronoUnit.MICROS),
                "createdAt must not be reset by a re-POST");
    }

    @Test
    void deleteReferencedCoachReturns409() throws Exception {
        // "Busy" authors a session (sessions are attributed to the JWT subject), so deleting Busy
        // must 409. Created through the API under Busy's own token so it lands in this test's club.
        Club club = clubs.findById(clubId).orElseThrow();
        UUID busyId = saveCoach("Busy", club);
        RequestPostProcessor busy = jwt().jwt(j -> j.subject(busyId.toString()).claim("club", clubId.toString()));

        mvc.perform(post("/api/sessions").with(busy).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"sessionName\":\"Practice\",\"scheduledDate\":\"2026-06-16\"}"))
                .andExpect(status().isCreated());

        mvc.perform(delete("/api/coaches/{id}", busyId).with(auth()))
                .andExpect(status().isConflict());
    }

    @Test
    void aPendingCoachWithoutAClubCannotManageCoaches() throws Exception {
        // No club claim -> ForbiddenException (403): a coach awaiting approval has no roster to manage.
        RequestPostProcessor pending = jwt().jwt(j -> j.subject(actingCoachId.toString()));
        mvc.perform(post("/api/coaches").with(pending).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Nope\"}"))
                .andExpect(status().isForbidden());
    }
}
