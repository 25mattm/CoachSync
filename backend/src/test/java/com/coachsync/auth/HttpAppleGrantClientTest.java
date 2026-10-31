package com.coachsync.auth;

import com.coachsync.auth.AppleGrantClient.Exchange;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.ECDSASigner;
import com.nimbusds.jose.crypto.ECDSAVerifier;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.interfaces.ECPrivateKey;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECGenParameterSpec;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/** Runs against a local stand-in for Apple's endpoints. */
class HttpAppleGrantClientTest {

    private static final String CLIENT_ID = "com.example.CoachSync";

    private HttpServer apple;
    private final List<String> paths = new ArrayList<>();
    private final List<Map<String, String>> forms = new ArrayList<>();
    private int status = 200;
    private String tokenBody;
    private KeyPair key;

    @BeforeEach
    void startApple() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
        generator.initialize(new ECGenParameterSpec("secp256r1"));
        key = generator.generateKeyPair();
        tokenBody = "{\"refresh_token\":\"refresh-1\",\"id_token\":\"" + idToken("apple-user-1") + "\"}";

        apple = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        apple.createContext("/", exchange -> {
            paths.add(exchange.getRequestURI().getPath());
            forms.add(parse(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8)));
            byte[] body = tokenBody.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(status, body.length);
            exchange.getResponseBody().write(body);
            exchange.close();
        });
        apple.start();
    }

    @AfterEach
    void stopApple() {
        apple.stop(0);
    }

    private String idToken(String subject) throws Exception {
        SignedJWT jwt = new SignedJWT(new JWSHeader(JWSAlgorithm.ES256),
                new JWTClaimsSet.Builder().subject(subject).build());
        jwt.sign(new ECDSASigner((ECPrivateKey) key.getPrivate()));
        return jwt.serialize();
    }

    private HttpAppleGrantClient client(int port) {
        String pem = "-----BEGIN PRIVATE KEY-----\n"
                + Base64.getMimeEncoder().encodeToString(key.getPrivate().getEncoded())
                + "\n-----END PRIVATE KEY-----";
        return new HttpAppleGrantClient(new AppleRevocationProperties("TEAM", "KEY", pem, "http://127.0.0.1:" + port));
    }

    private HttpAppleGrantClient client() {
        return client(apple.getAddress().getPort());
    }

    @Test
    void anAcceptedCodeReturnsTheAppleIdentityAndToken() throws Exception {
        Exchange result = client().exchange("the-code", CLIENT_ID);

        assertThat(result).isEqualTo(new Exchange.Confirmed("apple-user-1", "refresh-1", "refresh_token"));
        assertThat(paths).containsExactly("/auth/token");
        assertThat(forms.get(0)).containsEntry("code", "the-code")
                .containsEntry("client_id", CLIENT_ID)
                .containsEntry("grant_type", "authorization_code");

        SignedJWT secret = SignedJWT.parse(forms.get(0).get("client_secret"));
        assertThat(secret.verify(new ECDSAVerifier((ECPublicKey) key.getPublic()))).isTrue();
        assertThat(secret.getHeader().getKeyID()).isEqualTo("KEY");
        assertThat(secret.getJWTClaimsSet().getIssuer()).isEqualTo("TEAM");
        assertThat(secret.getJWTClaimsSet().getSubject()).isEqualTo(CLIENT_ID);
        assertThat(secret.getJWTClaimsSet().getAudience()).containsExactly("https://appleid.apple.com");
    }

    @Test
    void aBadCodeIsRejected() {
        status = 400;
        tokenBody = "{\"error\":\"invalid_grant\"}";

        assertThat(client().exchange("bad", CLIENT_ID)).isEqualTo(new Exchange.Rejected());
    }

    /** Our own misconfigured key says nothing about the coach, and mustn't stop their deletion. */
    @Test
    void aProblemWithOurCredentialsIsNotARejection() {
        status = 400;
        tokenBody = "{\"error\":\"invalid_client\"}";

        assertThat(client().exchange("code", CLIENT_ID)).isEqualTo(new Exchange.Unavailable());
    }

    @Test
    void aServerErrorAtAppleIsUnavailable() {
        status = 500;
        tokenBody = "{}";

        assertThat(client().exchange("code", CLIENT_ID)).isEqualTo(new Exchange.Unavailable());
    }

    @Test
    void aResponseWithoutAnIdentityIsUnavailable() {
        tokenBody = "{\"refresh_token\":\"refresh-1\"}";

        assertThat(client().exchange("code", CLIENT_ID)).isEqualTo(new Exchange.Unavailable());
    }

    @Test
    void revokeSendsTheTokenAndHint() {
        assertThat(client().revoke("refresh-1", "refresh_token", CLIENT_ID)).isTrue();

        assertThat(paths).containsExactly("/auth/revoke");
        assertThat(forms.get(0)).containsEntry("token", "refresh-1")
                .containsEntry("token_type_hint", "refresh_token");
    }

    @Test
    void aFailedRevokeReportsFalse() {
        status = 503;

        assertThat(client().revoke("refresh-1", "refresh_token", CLIENT_ID)).isFalse();
    }

    @Test
    void withoutCredentialsNothingIsCalled() {
        HttpAppleGrantClient unconfigured = new HttpAppleGrantClient(new AppleRevocationProperties("", "", "",
                "http://127.0.0.1:" + apple.getAddress().getPort()));

        assertThat(unconfigured.exchange("code", CLIENT_ID)).isEqualTo(new Exchange.Unavailable());
        assertThat(unconfigured.revoke("t", "refresh_token", CLIENT_ID)).isFalse();
        assertThat(paths).isEmpty();
    }

    /** The app gives up at 60 seconds, and a finished deletion mustn't look like a failure. */
    @Test
    void aServerThatNeverAnswersIsBoundedByTheTimeout() throws Exception {
        try (ServerSocket silent = new ServerSocket(0)) {
            long start = System.nanoTime();

            Exchange result = client(silent.getLocalPort()).exchange("code", CLIENT_ID);

            assertThat(result).isEqualTo(new Exchange.Unavailable());
            assertThat(Duration.ofNanos(System.nanoTime() - start)).isLessThan(Duration.ofSeconds(15));
        }
    }

    private static Map<String, String> parse(String form) {
        Map<String, String> values = new HashMap<>();
        for (String pair : form.split("&")) {
            String[] parts = pair.split("=", 2);
            values.put(URLDecoder.decode(parts[0], StandardCharsets.UTF_8),
                    parts.length > 1 ? URLDecoder.decode(parts[1], StandardCharsets.UTF_8) : "");
        }
        return values;
    }
}
