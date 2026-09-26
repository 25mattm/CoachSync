package com.coachsync.service;

import com.coachsync.domain.AthleteNote;
import com.coachsync.domain.CoachSession;
import com.coachsync.domain.SessionBlock;
import com.coachsync.repository.AthleteNoteRepository;
import com.coachsync.repository.CoachSessionRepository;
import com.coachsync.repository.SessionBlockRepository;
import com.coachsync.web.dto.BlockRequest;
import com.coachsync.web.dto.BlockResponse;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * Block CRUD. The edit guard ({@code assertEditAllowed}) and delete guard
 * ({@code assertDeletable}) protect recorded results. Slot (re)generation is
 * orchestrated by the controller AFTER these methods commit, so reconcile runs
 * in its own transaction (and can be retried on a concurrent-reconcile race).
 */
@Service
public class BlockService {

    private final SessionBlockRepository blocks;
    private final CoachSessionRepository sessions;
    private final AthleteNoteRepository notes;
    private final SlotGenerationService slotGeneration;

    public BlockService(SessionBlockRepository blocks,
                        CoachSessionRepository sessions,
                        AthleteNoteRepository notes,
                        SlotGenerationService slotGeneration) {
        this.blocks = blocks;
        this.sessions = sessions;
        this.notes = notes;
        this.slotGeneration = slotGeneration;
    }

    @Transactional(readOnly = true)
    public List<BlockResponse> listForSession(UUID sessionId) {
        if (!sessions.existsById(sessionId)) {
            throw new NotFoundException("No session with id " + sessionId);
        }
        return blocks.findBySessionIdOrderBySortOrderAsc(sessionId).stream()
                .map(BlockResponse::from)
                .toList();
    }

    @Transactional(readOnly = true)
    public BlockResponse get(UUID id) {
        return BlockResponse.from(getBlock(id));
    }

    @Transactional
    public BlockResponse create(UUID sessionId, BlockRequest request) {
        CoachSession session = sessions.findById(sessionId)
                .orElseThrow(() -> new NotFoundException("No session with id " + sessionId));
        if (request.id() != null) {
            var existing = blocks.findById(request.id());
            if (existing.isPresent()) {
                SessionBlock managed = existing.get();
                // An id already stored under a different session is a collision, not an upsert: updating
                // it here would leave the block in that other session while reporting success for this one.
                if (!managed.getSession().getId().equals(sessionId)) {
                    throw new ConflictException("A block with id " + request.id() + " already exists in another session.");
                }
                if (SyncTimestamps.isStale(managed, request.updatedAt())) {
                    return BlockResponse.from(managed);  // re-sent insert is older than the stored row — last-write-wins
                }
                // Same edit guard as update() — an insert+edit pair coalesced by the client's
                // outbox arrives here as a POST, not a PUT, and must be held to the same rule.
                int newRepetitionCount = request.repetitionCount() != null ? request.repetitionCount() : 1;
                slotGeneration.assertEditAllowed(managed, request.blockType(), newRepetitionCount);
                // Update the stored row in place — never new+save() (merge would reset the server-owned createdAt).
                apply(request, managed);
                return BlockResponse.from(blocks.save(managed));
            }
        }
        SessionBlock block = new SessionBlock();
        if (request.id() != null) {
            block.setId(request.id());
        }
        block.setSession(session);
        apply(request, block);
        return BlockResponse.from(blocks.save(block));
    }

    @Transactional
    public BlockResponse update(UUID id, BlockRequest request) {
        SessionBlock block = getBlock(id);
        if (SyncTimestamps.isStale(block, request.updatedAt())) {
            return BlockResponse.from(block);
        }
        int newRepetitionCount = request.repetitionCount() != null ? request.repetitionCount() : 1;
        slotGeneration.assertEditAllowed(block, request.blockType(), newRepetitionCount);
        apply(request, block);
        return BlockResponse.from(blocks.save(block));
    }

    @Transactional
    public void delete(UUID id) {
        SessionBlock block = getBlock(id);
        slotGeneration.assertDeletable(block);
        // A coaching note only ANCHORS to a block — it is recorded history owned by
        // the athlete/session. Null the anchor first so deleting the block preserves
        // the note (the block's rep-slot aggregate still cascades away). Mirrors
        // TeamService.delete nulling referencing sessions.
        List<AthleteNote> anchored = notes.findBySessionBlockId(id);
        for (AthleteNote note : anchored) {
            note.setSessionBlock(null);
        }
        notes.saveAll(anchored);
        blocks.delete(block);
    }

    private SessionBlock getBlock(UUID id) {
        return blocks.findById(id)
                .orElseThrow(() -> new NotFoundException("No block with id " + id));
    }

    private void apply(BlockRequest request, SessionBlock block) {
        block.setBlockName(request.blockName());
        block.setBlockType(request.blockType());
        block.setSortOrder(request.sortOrder() != null ? request.sortOrder() : 0);
        block.setRepetitionCount(request.repetitionCount() != null ? request.repetitionCount() : 1);
        block.setSetCount(request.setCount() != null ? request.setCount() : 1);
        block.setTargetDistanceMetres(request.targetDistanceMetres());
        block.setDistanceKm(request.distanceKm());
        block.setRestIntervalSeconds(request.restIntervalSeconds());
        block.setDurationSeconds(request.durationSeconds());
        block.setRequiresTimeEntry(request.requiresTimeEntry() == null || request.requiresTimeEntry());
        block.setTrainingZone(request.trainingZone());
        block.setDrillName(request.drillName());
        block.setCoachNote(request.coachNote());
        block.setPrescribedRepDurationsSec(request.prescribedRepDurationsSec() != null
                ? new ArrayList<>(request.prescribedRepDurationsSec())
                : new ArrayList<>());
        block.setUpdatedAt(SyncTimestamps.resolve(request.updatedAt()));
    }
}
