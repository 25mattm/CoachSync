package com.coachsync.service;

import com.coachsync.domain.Athlete;
import com.coachsync.domain.AthleteNote;
import com.coachsync.domain.Coach;
import com.coachsync.domain.CoachSession;
import com.coachsync.domain.SessionBlock;
import com.coachsync.repository.AthleteNoteRepository;
import com.coachsync.repository.AthleteRepository;
import com.coachsync.repository.CoachRepository;
import com.coachsync.repository.CoachSessionRepository;
import com.coachsync.repository.SessionBlockRepository;
import com.coachsync.web.dto.NoteCreateRequest;
import com.coachsync.web.dto.NoteResponse;
import com.coachsync.web.dto.NoteUpdateRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

@Service
public class NoteService {

    private final AthleteNoteRepository notes;
    private final AthleteRepository athletes;
    private final CoachSessionRepository sessions;
    private final SessionBlockRepository blocks;
    private final CoachRepository coaches;

    public NoteService(AthleteNoteRepository notes,
                       AthleteRepository athletes,
                       CoachSessionRepository sessions,
                       SessionBlockRepository blocks,
                       CoachRepository coaches) {
        this.notes = notes;
        this.athletes = athletes;
        this.sessions = sessions;
        this.blocks = blocks;
        this.coaches = coaches;
    }

    @Transactional(readOnly = true)
    public List<NoteResponse> forAthlete(UUID athleteId) {
        if (!athletes.existsById(athleteId)) {
            throw new NotFoundException("No athlete with id " + athleteId);
        }
        return notes.findByAthleteId(athleteId).stream().map(NoteResponse::from).toList();
    }

    @Transactional(readOnly = true)
    public List<NoteResponse> forSession(UUID sessionId) {
        if (!sessions.existsById(sessionId)) {
            throw new NotFoundException("No session with id " + sessionId);
        }
        return notes.findBySessionId(sessionId).stream().map(NoteResponse::from).toList();
    }

    @Transactional
    public NoteResponse create(UUID sessionId, NoteCreateRequest request, UUID creatorCoachId) {
        CoachSession session = sessions.findById(sessionId)
                .orElseThrow(() -> new NotFoundException("No session with id " + sessionId));
        Athlete athlete = athletes.findById(request.athleteId())
                .orElseThrow(() -> new NotFoundException("No athlete with id " + request.athleteId()));
        if (request.id() != null) {
            var existing = notes.findById(request.id());
            if (existing.isPresent()) {
                AthleteNote managed = existing.get();
                // An id already stored under a different session or athlete is a collision, not an upsert:
                // the note would keep its original session while the block anchor below is checked
                // against this one, leaving it anchored to a block from another session.
                if (!managed.getSession().getId().equals(sessionId)
                        || !managed.getAthlete().getId().equals(request.athleteId())) {
                    throw new ConflictException("A note with id " + request.id()
                            + " already exists for another session or athlete.");
                }
                if (SyncTimestamps.isStale(managed, request.updatedAt())) {
                    return NoteResponse.from(managed);  // re-sent insert is older than the stored row — last-write-wins
                }
                // Update the stored row in place and PRESERVE the original "logged by" coach — a fresh
                // new+save() would merge over it, resetting createdAt and re-stamping attribution.
                managed.setNoteText(request.noteText());
                applyBlockAnchor(request.sessionBlockId(), sessionId, managed);
                managed.setUpdatedAt(SyncTimestamps.resolve(request.updatedAt()));
                return NoteResponse.from(notes.save(managed));
            }
        }
        AthleteNote note = new AthleteNote();
        if (request.id() != null) {
            note.setId(request.id());
        }
        note.setSession(session);
        note.setAthlete(athlete);
        note.setNoteText(request.noteText());
        note.setCoach(resolveCoach(creatorCoachId));
        applyBlockAnchor(request.sessionBlockId(), sessionId, note);
        note.setUpdatedAt(SyncTimestamps.resolve(request.updatedAt()));
        return NoteResponse.from(notes.save(note));
    }

    @Transactional
    public NoteResponse update(UUID id, NoteUpdateRequest request) {
        AthleteNote note = getNote(id);
        if (SyncTimestamps.isStale(note, request.updatedAt())) {
            return NoteResponse.from(note);
        }
        note.setNoteText(request.noteText());
        // The "logged by" coach is fixed at create time; only text + block anchor change.
        applyBlockAnchor(request.sessionBlockId(), note.getSession().getId(), note);
        note.setUpdatedAt(SyncTimestamps.resolve(request.updatedAt()));
        return NoteResponse.from(notes.save(note));
    }

    @Transactional
    public void delete(UUID id) {
        notes.delete(getNote(id));
    }

    private void applyBlockAnchor(UUID blockId, UUID sessionId, AthleteNote note) {
        if (blockId == null) {
            note.setSessionBlock(null);
        } else {
            SessionBlock block = blocks.findById(blockId)
                    .orElseThrow(() -> new NotFoundException("No block with id " + blockId));
            if (!block.getSession().getId().equals(sessionId)) {
                throw new BadRequestException("Block " + blockId + " does not belong to the note's session.");
            }
            note.setSessionBlock(block);
        }
    }

    /** Resolves the authenticated coach who is the note's creator/"logged by". */
    private Coach resolveCoach(UUID coachId) {
        return coaches.findById(coachId)
                .orElseThrow(() -> new NotFoundException("No coach with id " + coachId));
    }

    private AthleteNote getNote(UUID id) {
        return notes.findById(id)
                .orElseThrow(() -> new NotFoundException("No note with id " + id));
    }
}
