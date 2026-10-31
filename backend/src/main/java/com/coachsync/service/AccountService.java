package com.coachsync.service;

import com.coachsync.auth.AppleTokenRevoker;
import com.coachsync.auth.AuthProperties;
import com.coachsync.web.dto.DeleteAccountRequest;
import org.springframework.stereotype.Service;

/**
 * Deletes the signed-in coach's own account: App Store Review Guideline 5.1.1(v). Not transactional
 * itself, so the network call to Apple never holds a database transaction open.
 */
@Service
public class AccountService {

    private final AppleTokenRevoker revoker;
    private final CoachService coaches;
    private final AuthProperties auth;

    public AccountService(AppleTokenRevoker revoker, CoachService coaches, AuthProperties auth) {
        this.revoker = revoker;
        this.coaches = coaches;
        this.auth = auth;
    }

    public void deleteOwnAccount(DeleteAccountRequest request) {
        if (!auth.apple().clientIds().contains(request.clientId())) {
            throw new BadRequestException("Unknown client id.");
        }
        coaches.deleteOwnAccount();
        revoker.revoke(request.authorizationCode(), request.clientId());
    }
}
