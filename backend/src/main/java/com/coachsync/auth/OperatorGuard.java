package com.coachsync.auth;

import com.coachsync.domain.Coach;
import com.coachsync.repository.CoachRepository;
import com.coachsync.service.ForbiddenException;
import org.springframework.stereotype.Component;

import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Gates the platform-operator actions: creating a club and approving a coach into one. There is no
 * admin role on {@link Coach} — {@code coachsync.auth.allowed-emails} (the former sign-in allowlist,
 * repurposed per the multi-club tenancy plan's settled slice 4 design) is now the operator gate
 * instead: only a signed-in coach whose email is on that list may call the two operator-only
 * endpoints. Ordinary data access no longer depends on this list at all.
 */
@Component
public class OperatorGuard {

    private final CoachRepository coaches;
    private final ClubTenantResolver tenant;
    private final Set<String> allowedEmails;

    public OperatorGuard(CoachRepository coaches, ClubTenantResolver tenant, AuthProperties properties) {
        this.coaches = coaches;
        this.tenant = tenant;
        this.allowedEmails = properties.allowedEmails().stream()
                .filter(e -> e != null && !e.isBlank())
                .map(OperatorGuard::normalize)
                .collect(Collectors.toUnmodifiableSet());
    }

    /** Throws {@link ForbiddenException} unless the caller is signed in and on the operator allowlist. */
    public void requireOperator() {
        UUID id = tenant.currentCoachId().orElseThrow(OperatorGuard::notOperator);
        Coach coach = coaches.findById(id).orElseThrow(OperatorGuard::notOperator);
        String email = coach.getEmail();
        if (email == null || !allowedEmails.contains(normalize(email))) {
            throw notOperator();
        }
    }

    private static ForbiddenException notOperator() {
        return new ForbiddenException("Only the platform operator may do this.");
    }

    private static String normalize(String email) {
        return email.trim().toLowerCase(Locale.ROOT);
    }
}
