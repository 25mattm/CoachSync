package com.coachsync.auth;

/**
 * Revokes the app's Sign in with Apple grant when a coach deletes their account, as Apple requires
 * of any app offering that sign-in. Deleting the account never depends on this succeeding: a coach's
 * right to delete their data outranks a failed call to Apple, so failures are logged, not thrown.
 */
public interface AppleTokenRevoker {

    /**
     * @param authorizationCode the short-lived code from a fresh Apple authorization.
     * @param clientId          the bundle ID the code was issued for, already validated by the caller.
     */
    void revoke(String authorizationCode, String clientId);
}
