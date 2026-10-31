package com.coachsync.service;

import com.coachsync.auth.AppleGrantClient;
import com.coachsync.auth.AppleGrantClient.Exchange;
import com.coachsync.auth.AuthProperties;
import com.coachsync.web.dto.DeleteAccountRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * Deletes the signed-in coach's own account: App Store Review Guideline 5.1.1(v). Not transactional
 * itself, so the network calls to Apple never hold a database transaction open.
 *
 * <p>Apple is asked first, so that a bearer token alone can't delete an account. Only a definite
 * refusal stops it: if Apple can't answer, the deletion goes ahead, since an outage must not stand
 * between a coach and deleting their data.
 */
@Service
public class AccountService {

    private static final Logger log = LoggerFactory.getLogger(AccountService.class);

    private final AppleGrantClient apple;
    private final AppleRevocationQueue revocations;
    private final CoachService coaches;
    private final AuthProperties auth;

    public AccountService(AppleGrantClient apple, AppleRevocationQueue revocations, CoachService coaches,
                          AuthProperties auth) {
        this.apple = apple;
        this.revocations = revocations;
        this.coaches = coaches;
        this.auth = auth;
    }

    public void deleteOwnAccount(DeleteAccountRequest request) {
        if (!auth.apple().clientIds().contains(request.clientId())) {
            throw new BadRequestException("Unknown client id.");
        }
        String appleUserId = coaches.currentCoachAppleUserId();
        switch (apple.exchange(request.authorizationCode(), request.clientId())) {
            case Exchange.Rejected rejected ->
                    throw new ForbiddenException("Apple didn't confirm this authorization.");
            case Exchange.Unavailable unavailable -> {
                coaches.deleteOwnAccount();
                log.error("Account deleted without Apple confirmation or grant revocation");
            }
            case Exchange.Confirmed confirmed -> {
                if (!confirmed.appleUserId().equals(appleUserId)) {
                    throw new ForbiddenException("This authorization is for a different Apple ID.");
                }
                coaches.deleteOwnAccount();
                revocations.revokeOrQueue(confirmed.token(), confirmed.tokenTypeHint(), request.clientId());
            }
        }
    }
}
