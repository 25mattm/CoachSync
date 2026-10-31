package com.coachsync.auth;

import com.nimbusds.jose.JOSEException;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.ECDSASigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.interfaces.ECPrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.Date;
import java.util.Map;

/**
 * Exchanges the authorization code for a token, then revokes that token. The two-step shape is
 * Apple's: {@code /auth/revoke} takes a token, not a code. See TN3194.
 */
@Component
public class HttpAppleTokenRevoker implements AppleTokenRevoker {

    private static final Logger log = LoggerFactory.getLogger(HttpAppleTokenRevoker.class);
    private static final Duration CLIENT_SECRET_TTL = Duration.ofMinutes(5);

    private final AppleRevocationProperties properties;
    private final RestClient http;

    public HttpAppleTokenRevoker(AppleRevocationProperties properties) {
        this.properties = properties;
        this.http = RestClient.create(properties.baseUrl());
    }

    @Override
    public void revoke(String authorizationCode, String clientId) {
        if (!properties.isConfigured()) {
            log.warn("Sign in with Apple grant not revoked: Apple revocation credentials are not set");
            return;
        }
        try {
            String clientSecret = clientSecret(clientId);
            Map<String, Object> tokens = exchange(authorizationCode, clientId, clientSecret);
            Object refreshToken = tokens == null ? null : tokens.get("refresh_token");
            Object token = refreshToken != null ? refreshToken : (tokens == null ? null : tokens.get("access_token"));
            if (token == null) {
                log.warn("Sign in with Apple grant not revoked: Apple returned no token");
                return;
            }
            revokeToken(token.toString(), refreshToken != null ? "refresh_token" : "access_token",
                    clientId, clientSecret);
        } catch (RestClientException | JOSEException | GeneralSecurityException | IllegalArgumentException ex) {
            // Only the exception type: Apple's error bodies and our inputs carry credentials.
            log.warn("Sign in with Apple grant not revoked: {}", ex.getClass().getSimpleName());
        }
    }

    private Map<String, Object> exchange(String code, String clientId, String clientSecret) {
        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("client_id", clientId);
        form.add("client_secret", clientSecret);
        form.add("code", code);
        form.add("grant_type", "authorization_code");
        return http.post().uri("/auth/token")
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .body(form)
                .retrieve()
                .body(new ParameterizedTypeReference<>() {});
    }

    private void revokeToken(String token, String hint, String clientId, String clientSecret) {
        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("client_id", clientId);
        form.add("client_secret", clientSecret);
        form.add("token", token);
        form.add("token_type_hint", hint);
        http.post().uri("/auth/revoke")
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .body(form)
                .retrieve()
                .toBodilessEntity();
    }

    /** Apple's client secret is a short-lived ES256 JWT signed with the Sign in with Apple key. */
    private String clientSecret(String clientId) throws JOSEException, GeneralSecurityException {
        Instant now = Instant.now();
        SignedJWT jwt = new SignedJWT(
                new JWSHeader.Builder(JWSAlgorithm.ES256).keyID(properties.keyId()).build(),
                new JWTClaimsSet.Builder()
                        .issuer(properties.teamId())
                        .subject(clientId)
                        .audience("https://appleid.apple.com")
                        .issueTime(Date.from(now))
                        .expirationTime(Date.from(now.plus(CLIENT_SECRET_TTL)))
                        .build());
        jwt.sign(new ECDSASigner(privateKey()));
        return jwt.serialize();
    }

    private ECPrivateKey privateKey() throws GeneralSecurityException {
        String base64 = properties.privateKey()
                .replace("\\n", "\n")
                .replaceAll("-----(BEGIN|END) PRIVATE KEY-----", "")
                .replaceAll("\\s", "");
        return (ECPrivateKey) KeyFactory.getInstance("EC")
                .generatePrivate(new PKCS8EncodedKeySpec(Base64.getDecoder().decode(base64)));
    }
}
