package com.coachsync.service;

import com.coachsync.auth.ClubTenantResolver;
import com.coachsync.auth.OperatorGuard;
import com.coachsync.domain.Club;
import com.coachsync.domain.Coach;
import com.coachsync.domain.Timestamps;
import com.coachsync.repository.AthleteNoteRepository;
import com.coachsync.repository.ClubRepository;
import com.coachsync.repository.CoachRepository;
import com.coachsync.repository.CoachSessionRepository;
import com.coachsync.repository.DevelopmentNoteRepository;
import com.coachsync.web.dto.CoachRequest;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

/**
 * {@code Coach} is un-tenanted (it is resolved before any club is known — see {@link Coach#getClub()}),
 * so Hibernate's {@code @TenantId} filter does not scope it and every read/write here must be scoped
 * to the caller's club <em>by hand</em>. The caller's club comes from {@link ClubTenantResolver}, the
 * same source Hibernate uses for the tenant-scoped entities, so there is one definition of "current
 * club". A caller with no club (anonymous or awaiting approval) sees no coaches and may not write.
 */
@Service
public class CoachService {

    /** Shown wherever a deleted coach is still attributed on club history. */
    static final String DELETED_COACH_NAME = "Former coach";

    private final CoachRepository coaches;
    private final CoachSessionRepository sessions;
    private final AthleteNoteRepository notes;
    private final DevelopmentNoteRepository journal;
    private final ClubRepository clubs;
    private final ClubTenantResolver tenant;
    private final OperatorGuard operatorGuard;

    public CoachService(CoachRepository coaches,
                        CoachSessionRepository sessions,
                        AthleteNoteRepository notes,
                        DevelopmentNoteRepository journal,
                        ClubRepository clubs,
                        ClubTenantResolver tenant,
                        OperatorGuard operatorGuard) {
        this.coaches = coaches;
        this.sessions = sessions;
        this.notes = notes;
        this.journal = journal;
        this.clubs = clubs;
        this.tenant = tenant;
        this.operatorGuard = operatorGuard;
    }

    @Transactional(readOnly = true)
    public Page<Coach> list(Pageable pageable) {
        return tenant.currentClubId()
                .map(clubId -> coaches.findByClub_Id(clubId, pageable))
                .orElseGet(() -> Page.empty(pageable));
    }

    @Transactional(readOnly = true)
    public Coach get(UUID id) {
        Coach coach = coaches.findById(id)
                .orElseThrow(() -> new NotFoundException("No coach with id " + id));
        // A coach in another club (or none) is indistinguishable from one that does not exist — the
        // same 404 the tenant filter produces for the scoped entities, so the API never confirms a
        // cross-club id.
        if (!inCurrentClub(coach)) {
            throw new NotFoundException("No coach with id " + id);
        }
        return coach;
    }

    @Transactional
    public Coach create(CoachRequest request) {
        UUID clubId = requireClub();
        if (request.id() != null) {
            var existing = coaches.findById(request.id());
            if (existing.isPresent()) {
                Coach managed = existing.get();
                // The lookup is un-tenanted, so a re-POST of another club's coach id would otherwise
                // update THAT club's row from here. Refuse it as a collision (409) rather than write
                // across clubs — mirrors the create-by-id guard the tenant-scoped roots get in slice 3.
                if (!inCurrentClub(managed)) {
                    throw new ConflictException("A coach with id " + request.id() + " already exists.");
                }
                refuseIfDeleted(managed);
                if (SyncTimestamps.isStale(managed, request.updatedAt())) {
                    return managed;  // re-sent insert is older than the stored row — last-write-wins
                }
                // Update the stored row in place — a fresh new+save() would merge over it and wipe the
                // server-owned fields the request never carries (appleUserId/email/createdAt = the auth link).
                apply(request, managed);
                return coaches.save(managed);
            }
        }
        Coach coach = new Coach();
        if (request.id() != null) {
            coach.setId(request.id());
        }
        coach.setClub(clubs.getReferenceById(clubId));
        apply(request, coach);
        return coaches.save(coach);
    }

    @Transactional
    public Coach update(UUID id, CoachRequest request) {
        Coach coach = get(id);   // 404s across clubs before any write
        refuseIfDeleted(coach);
        if (SyncTimestamps.isStale(coach, request.updatedAt())) {
            return coach;
        }
        apply(request, coach);
        return coaches.save(coach);
    }

    /**
     * Deletes a coach only if nothing references them. A coach attributed on a
     * session or note cannot be deleted (that attribution would be lost / would
     * violate the FK); reassign or remove those first. Another coach's signed-in (Apple-linked)
     * account cannot be deleted at all — only its owner may remove it.
     */
    @Transactional
    public void delete(UUID id) {
        Coach coach = get(id);   // 404s across clubs before the reference guard even runs
        // A row with an Apple link is a person's sign-in account, not just a roster profile. Deleting
        // it revokes their token on the next request (ActiveCoachFilter) and drops them back to
        // pending approval, so only that coach may remove their own account — never a clubmate.
        boolean isCallerSelf = tenant.currentCoachId().map(id::equals).orElse(false);
        if (coach.getAppleUserId() != null && !isCallerSelf) {
            throw new ConflictException("Coach " + id + " is another coach's signed-in account and "
                    + "cannot be deleted by a clubmate.");
        }
        if (sessions.existsByCoachId(id) || notes.existsByCoachId(id) || journal.existsByCoachId(id)) {
            throw new ConflictException("Coach " + id + " is referenced by sessions, notes, or journal "
                    + "entries and cannot be deleted; reassign or remove them first.");
        }
        coaches.delete(coach);
    }

    /**
     * Deletes the caller's own account. The sign-in identity and personal details always go. A coach
     * attributed on the club's sessions, notes or journal entries keeps an anonymous row so that club
     * history survives; one with nothing attributed is removed outright. Clearing
     * {@code appleUserId} revokes every outstanding token ({@code ActiveCoachFilter}), and signing in
     * again later provisions a brand-new coach with no club. Stamping {@code updatedAt} is what makes
     * clubmates' devices take the change on their next pull.
     */
    @Transactional
    public void deleteOwnAccount() {
        Coach coach = currentCoach();
        UUID id = coach.getId();
        if (sessions.existsByCoachId(id) || notes.existsByCoachId(id) || journal.existsByCoachId(id)) {
            coach.setName(DELETED_COACH_NAME);
            coach.setAppleUserId(null);
            coach.setEmail(null);
            coach.setRole(null);
            coach.setNccpLevel(null);
            coach.setColorHex(null);
            coach.setRequestedClub(null);
            coach.setDeletedAt(Timestamps.now());
            coach.setUpdatedAt(coach.getDeletedAt());
            coaches.save(coach);
        } else {
            coaches.delete(coach);
        }
    }

    /** The caller's Apple identity, to check a deletion's authorization against. */
    @Transactional(readOnly = true)
    public String currentCoachAppleUserId() {
        return currentCoach().getAppleUserId();
    }

    private Coach currentCoach() {
        UUID id = tenant.currentCoachId()
                .orElseThrow(() -> new ForbiddenException("Only a signed-in coach can delete their account."));
        return coaches.findById(id)
                .orElseThrow(() -> new NotFoundException("No coach with id " + id));
    }

    /** A clubmate's device still holding a deleted coach must not be able to write them back. */
    private static void refuseIfDeleted(Coach coach) {
        if (coach.getDeletedAt() != null) {
            throw new ConflictException("Coach " + coach.getId() + " has deleted their account.");
        }
    }

    /**
     * Operator-only: every coach with a pending join request, platform-wide. Deliberately un-tenanted
     * — the operator is not a member of any one club, they administer the platform.
     */
    @Transactional(readOnly = true)
    public List<Coach> pending() {
        operatorGuard.requireOperator();
        return coaches.findByRequestedClubIsNotNull();
    }

    /**
     * Operator-only: approves a pending coach into the club they requested, clearing the request.
     * Un-tenanted lookup by design — same reasoning as {@link #pending()}, and the very first coach
     * ever approved (into the very first club) could not otherwise be reached by a club-scoped {@code
     * get}. The coach's next issued token carries the {@code club} claim; this one stays stale until
     * they sign in again.
     */
    @Transactional
    public Coach approve(UUID id) {
        operatorGuard.requireOperator();
        Coach coach = coaches.findById(id)
                .orElseThrow(() -> new NotFoundException("No coach with id " + id));
        Club requested = coach.getRequestedClub();
        if (requested == null) {
            throw new ConflictException("Coach " + id + " has no pending club join request.");
        }
        coach.setClub(requested);
        coach.setRequestedClub(null);
        return coaches.save(coach);
    }

    /**
     * Operator-only: removes a coach from their club, for when a coach leaves or is dismissed.
     * {@code ActiveCoachFilter} rejects the coach's outstanding tokens on their next request, and any
     * later sign-in issues a token with no {@code club} claim, so getting back in means a new join
     * request and a new approval. Only membership changes: the row stays so that sessions, notes and
     * journal entries keep their attribution. Un-tenanted lookup, same reasoning as {@link #approve}.
     */
    @Transactional
    public Coach removeFromClub(UUID id) {
        operatorGuard.requireOperator();
        Coach coach = coaches.findById(id)
                .orElseThrow(() -> new NotFoundException("No coach with id " + id));
        if (coach.getClub() == null) {
            throw new ConflictException("Coach " + id + " does not belong to a club.");
        }
        coach.setClub(null);
        return coaches.save(coach);
    }

    /** True only when the coach is in the caller's club. A club-less coach belongs to no caller. */
    private boolean inCurrentClub(Coach coach) {
        UUID current = tenant.currentClubId().orElse(null);
        return current != null
                && coach.getClub() != null
                && current.equals(coach.getClub().getId());
    }

    /**
     * The caller's club, or a 403 — a coach awaiting approval may not manage a roster.
     *
     * <p>Redundant with {@code ClubMembershipWriteGuard} for genuine bearer-token callers (that
     * filter already rejects a club-less {@code POST /api/coaches} before this is ever reached) —
     * but NOT for {@code @WithMockUser}-authenticated test requests, which the filter's own javadoc
     * says it deliberately never inspects. Keep this: it's the only guard those requests still hit.
     */
    private UUID requireClub() {
        return tenant.currentClubId().orElseThrow(() ->
                new ForbiddenException("You must belong to a club to manage coaches."));
    }

    private void apply(CoachRequest request, Coach coach) {
        coach.setName(request.name());
        coach.setRole(request.role());
        coach.setNccpLevel(request.nccpLevel());
        coach.setColorHex(request.colorHex());
        coach.setUpdatedAt(SyncTimestamps.resolve(request.updatedAt()));
    }
}
