package com.coachsync;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.context.annotation.Bean;

import java.time.Clock;
import java.time.ZoneId;

/**
 * Entry point for the CoachSync backend — the training-log REST API plus
 * read-only analytics. See {@code coachsync-training-log-data-model.md}.
 */
@SpringBootApplication
@EnableScheduling
public class CoachSyncBackendApplication {

    public static void main(String[] args) {
        SpringApplication.run(CoachSyncBackendApplication.class, args);
    }

    /**
     * Season/age-category clock, injected wherever the current season year is derived
     * ({@code SeasonContext}). Pinned to the club's own timezone rather than
     * {@code Clock.systemDefaultZone()} — a cloud host's container defaults to UTC, which would
     * flip the season year / age category up to several hours before or after the club's coaches
     * see it happen on their own phones (device-local {@code Calendar.current}).
     */
    @Bean
    Clock clock() {
        return Clock.system(ZoneId.of("America/Toronto"));
    }
}
