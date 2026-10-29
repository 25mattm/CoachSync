package com.coachsync.service;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.Timestamps;
import com.coachsync.domain.enums.DevelopmentStage;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.web.dto.AthleteRequest;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

@Service
public class AthleteService {

    private final AthleteRepository athletes;
    private final AthleteHistoryGuard history;

    public AthleteService(AthleteRepository athletes, AthleteHistoryGuard history) {
        this.athletes = athletes;
        this.history = history;
    }

    @Transactional(readOnly = true)
    public Page<Athlete> list(Boolean active, Pageable pageable) {
        return active == null
                ? athletes.findAll(pageable)
                : athletes.findByIsActive(active, pageable);
    }

    @Transactional(readOnly = true)
    public Athlete get(UUID id) {
        return athletes.findById(id)
                .orElseThrow(() -> new NotFoundException("No athlete with id " + id));
    }

    @Transactional
    public Athlete create(AthleteRequest request) {
        // NOTE (reviewed, intentionally not hardened): the findById→save below is a check-then-insert
        // that isn't atomic, so two *concurrent* POSTs of the same not-yet-stored id could both insert,
        // and one would hit the PK constraint (409). In this sync model that can't arise — ids are
        // random per device and each device's pusher is serial — and no data is lost if it did (the
        // winning insert stands). A fresh-transaction retry across every create service wasn't justified.
        if (request.id() != null) {
            var existing = athletes.findById(request.id());
            if (existing.isPresent()) {
                Athlete managed = existing.get();
                if (SyncTimestamps.isStale(managed, request.updatedAt())) {
                    return managed;  // re-sent insert is older than the stored row — last-write-wins
                }
                // Update the stored row in place — a fresh new+save() would merge over it and reset the
                // server-owned createdAt the request never carries.
                apply(request, managed);
                return athletes.save(managed);
            }
        }
        Athlete athlete = new Athlete();
        if (request.id() != null) {
            athlete.setId(request.id());
        }
        apply(request, athlete);
        return athletes.save(athlete);
    }

    @Transactional
    public Athlete update(UUID id, AthleteRequest request) {
        Athlete athlete = get(id);
        if (SyncTimestamps.isStale(athlete, request.updatedAt())) {
            return athlete;
        }
        apply(request, athlete);
        return athletes.save(athlete);
    }

    /**
     * Direct active/inactive toggle (PATCH /active), separate from the LWW-merged full PUT the sync
     * path uses for the {@code active} field. The server-stamped {@code updatedAt} is intentional:
     * this endpoint carries no client timestamp because it's a deliberate, server-authoritative
     * action — an explicit toggle should take effect, not be gated by last-write-wins.
     */
    @Transactional
    public Athlete setActive(UUID id, boolean active) {
        Athlete athlete = get(id);
        athlete.setActive(active);
        athlete.setUpdatedAt(Timestamps.now());
        return athletes.save(athlete);
    }

    /**
     * Deletes an athlete only if they have no recorded history (see
     * {@link AthleteHistoryGuard}). Athletes with history must be marked inactive
     * instead.
     */
    @Transactional
    public void delete(UUID id) {
        Athlete athlete = get(id);
        if (history.hasRecordedHistory(id)) {
            throw new ConflictException(
                    "Athlete " + id + " has recorded practice history and cannot be deleted; "
                            + "mark them inactive instead.");
        }
        athletes.delete(athlete);
    }

    private void apply(AthleteRequest request, Athlete athlete) {
        athlete.setFirstName(request.firstName());
        athlete.setLastName(request.lastName());
        athlete.setDateOfBirth(request.dateOfBirth());
        athlete.setGender(request.gender());
        athlete.setGuardianName(request.guardianName());
        athlete.setGuardianPhone(request.guardianPhone());
        athlete.setGuardianEmail(request.guardianEmail());
        // Full-replace semantics: an omitted stage resets to the default rather
        // than keeping the previous value (developmentStage is non-nullable).
        athlete.setDevelopmentStage(request.developmentStage() != null
                ? request.developmentStage()
                : DevelopmentStage.INITIATION);
        if (request.active() != null) athlete.setActive(request.active());
        athlete.setUpdatedAt(SyncTimestamps.resolve(request.updatedAt()));
    }
}
