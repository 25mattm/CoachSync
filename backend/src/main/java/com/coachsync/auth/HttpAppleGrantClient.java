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
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;

import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.interfaces.ECPrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.text.ParseException;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.Date;
import java.util.Map;

/**
 * Calls Apple's token endpoints. See TN3194. Time limits keep the whole deletion request well under
 * the app's 60-second timeout, so a stalled Apple can't make a finished deletion look like a failure.
 *
 * <p>Logs only exception types: Apple's error bodies and our inputs carry credentials.
 */
@Component
public class HttpAppleGrantClient implements AppleGrantClient {

    private static final Logger log = LoggerFactory.getLogger(HttpAppleGrantClient.class);
    private static final Duration CONNECT_TIMEOUT = Duration.ofSeconds(3);
    private static final Duration READ_TIMEOUT = Duration.ofSeconds(5);
    private static final Duration CLIENT_SECRET_TTL = Duration.ofMinutes(5);

    private final AppleRevocationProperties properties;
    private final RestClient http;

    public HttpAppleGrantClient(AppleRevocationProperties properties) {
        this.properties = properties;
        SimpleClientHttpRequestFactory requests = new SimpleClientHttpRequestFactory();
        requests.setConnectTimeout(CONNECT_TIMEOUT);
        requests.setReadTimeout(READ_TIMEOUT);
        this.http = RestClient.builder().baseUrl(properties.baseUrl()).requestFactory(requests).build();
    }

    @Override
    public Exchange exchange(String authorizationCode, String clientId) {
        if (!properties.isConfigured()) {
            log.warn("Apple authorization not checked: Apple credentials are not set");
            return new Exchange.Unavailable();
        }
        try {
            MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
            form.add("client_id", clientId);
            form.add("client_secret", clientSecret(clientId));
            form.add("code", authorizationCode);
            form.add("grant_type", "authorization_code");
            Map<String, Object> tokens = http.post().uri("/auth/token")
                    .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                    .body(form)
                    .retrieve()
                    .body(new ParameterizedTypeReference<>() {});
            return confirmed(tokens);
        } catch (HttpClientErrorException ex) {
            // Only invalid_grant is about the code. Others, like invalid_client, are about our key,
            // and a mistake of ours must not stop a coach deleting their account.
            if (ex.getResponseBodyAsString().contains("invalid_grant")) {
                return new Exchange.Rejected();
            }
            log.error("Apple refused our credentials: HTTP {}", ex.getStatusCode().value());
            return new Exchange.Unavailable();
        } catch (RuntimeException | JOSEException | GeneralSecurityException | ParseException ex) {
            log.warn("Apple authorization not checked: {}", ex.getClass().getSimpleName());
            return new Exchange.Unavailable();
        }
    }

    private static Exchange confirmed(Map<String, Object> tokens) throws ParseException {
        Object idToken = tokens == null ? null : tokens.get("id_token");
        Object refreshToken = tokens == null ? null : tokens.get("refresh_token");
        Object accessToken = tokens == null ? null : tokens.get("access_token");
        if (idToken == null || (refreshToken == null && accessToken == null)) {
            log.warn("Apple authorization not checked: incomplete token response");
            return new Exchange.Unavailable();
        }
        // Received directly from Apple over TLS, so OpenID Connect doesn't require checking the
        // signature here.
        String subject = SignedJWT.parse(idToken.toString()).getJWTClaimsSet().getSubject();
        return refreshToken != null
                ? new Exchange.Confirmed(subject, refreshToken.toString(), "refresh_token")
                : new Exchange.Confirmed(subject, accessToken.toString(), "access_token");
    }

    @Override
    public boolean revoke(String token, String tokenTypeHint, String clientId) {
        if (!properties.isConfigured()) {
            return false;
        }
        try {
            MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
            form.add("client_id", clientId);
            form.add("client_secret", clientSecret(clientId));
            form.add("token", token);
            form.add("token_type_hint", tokenTypeHint);
            http.post().uri("/auth/revoke")
                    .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                    .body(form)
                    .retrieve()
                    .toBodilessEntity();
            return true;
        } catch (RuntimeException | JOSEException | GeneralSecurityException ex) {
            log.warn("Apple grant not revoked: {}", ex.getClass().getSimpleName());
            return false;
        }
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
        jwt.sign(new ECDSASigner(parsePrivateKey(properties.privateKey())));
        return jwt.serialize();
    }

    /** Package-private so the prod guard can reject an unusable key at startup. */
    static ECPrivateKey parsePrivateKey(String pem) throws GeneralSecurityException {
        String base64 = pem
                .replace("\\n", "\n")
                .replaceAll("-----(BEGIN|END) PRIVATE KEY-----", "")
                .replaceAll("\\s", "");
        return (ECPrivateKey) KeyFactory.getInstance("EC")
                .generatePrivate(new PKCS8EncodedKeySpec(Base64.getDecoder().decode(base64)));
    }
}
