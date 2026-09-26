package com.coachsync.service;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.Coach;
import com.coachsync.domain.DevelopmentNote;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.CoachRepository;
import com.coachsync.repository.DevelopmentNoteRepository;
import com.coachsync.web.dto.JournalRequest;
import com.coachsync.web.dto.JournalResponse;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * Development-journal CRUD. Response mapping (lazy tags + coach) happens inside the
 * transaction. The "logged by" coach is the authenticated creator, set at create time
 * and preserved on update.
 */
@Service
public class DevelopmentNoteService {

    private final DevelopmentNoteRepository journal;
    private final AthleteRepository athletes;
    private final CoachRepository coaches;

    public DevelopmentNoteService(DevelopmentNoteRepository journal,
                                  AthleteRepository athletes,
                                  CoachRepository coaches) {
        this.journal = journal;
        this.athletes = athletes;
        this.coaches = coaches;
    }

    @Transactional(readOnly = true)
    public List<JournalResponse> listForAthlete(UUID athleteId) {
        if (!athletes.existsById(athleteId)) {
            throw new NotFoundException("No athlete with id " + athleteId);
        }
        return journal.findByAthleteId(athleteId).stream().map(JournalResponse::from).toList();
    }

    @Transactional(readOnly = true)
    public JournalResponse get(UUID id) {
        return JournalResponse.from(getNote(id));
    }

    @Transactional
    public JournalResponse create(UUID athleteId, JournalRequest request, UUID creatorCoachId) {
        Athlete athlete = athletes.findById(athleteId)
                .orElseThrow(() -> new NotFoundException("No athlete with id " + athleteId));
        if (request.id() != null) {
            var existing = journal.findById(request.id());
            if (existing.isPresent()) {
                DevelopmentNote managed = existing.get();
                // An id already stored under a different athlete is a collision, not an upsert: updating
                // it here would leave the row on that other athlete while reporting success for this one.
                if (!managed.getAthlete().getId().equals(athleteId)) {
                    throw new ConflictException("A record with id " + request.id() + " already exists for another athlete.");
                }
                if (SyncTimestamps.isStale(managed, request.updatedAt())) {
                    return JournalResponse.from(managed);  // re-sent insert is older than the stored row — last-write-wins
                }
                // Update the stored row in place and PRESERVE the original "logged by" coach — a fresh
                // new+save() would merge over it, resetting createdAt and re-stamping attribution.
                apply(request, managed);
                return JournalResponse.from(journal.save(managed));
            }
        }
        DevelopmentNote note = new DevelopmentNote();
        if (request.id() != null) {
            note.setId(request.id());
        }
        note.setAthlete(athlete);
        apply(request, note);
        note.setCoach(resolveCoach(creatorCoachId));
        return JournalResponse.from(journal.save(note));
    }

    @Transactional
    public JournalResponse update(UUID id, JournalRequest request) {
        DevelopmentNote note = getNote(id);
        if (SyncTimestamps.isStale(note, request.updatedAt())) {
            return JournalResponse.from(note);
        }
        apply(request, note);  // the "logged by" coach is fixed at create time
        return JournalResponse.from(journal.save(note));
    }

    @Transactional
    public void delete(UUID id) {
        journal.delete(getNote(id));
    }

    private DevelopmentNote getNote(UUID id) {
        return journal.findById(id)
                .orElseThrow(() -> new NotFoundException("No journal note with id " + id));
    }

    private void apply(JournalRequest request, DevelopmentNote note) {
        note.setDate(request.date());
        note.setText(request.text());
        note.setTags(request.tags() != null ? new ArrayList<>(request.tags()) : new ArrayList<>());
        note.setUpdatedAt(SyncTimestamps.resolve(request.updatedAt()));
    }

    /** Resolves the authenticated coach who is the journal entry's creator/"logged by". */
    private Coach resolveCoach(UUID coachId) {
        return coaches.findById(coachId)
                .orElseThrow(() -> new NotFoundException("No coach with id " + coachId));
    }
}
