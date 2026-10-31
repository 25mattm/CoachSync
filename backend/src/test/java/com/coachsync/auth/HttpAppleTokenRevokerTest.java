package com.coachsync.auth;

import com.nimbusds.jose.crypto.ECDSAVerifier;
import com.nimbusds.jwt.SignedJWT;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECGenParameterSpec;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;

/** Runs the two-step exchange and revoke against a local stand-in for Apple's endpoints. */
class HttpAppleTokenRevokerTest {

    private HttpServer apple;
    private final List<String> paths = new ArrayList<>();
    private final List<Map<String, String>> forms = new ArrayList<>();
    private int tokenStatus = 200;
    private KeyPair key;

    @BeforeEach
    void startApple() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
        generator.initialize(new ECGenParameterSpec("secp256r1"));
        key = generator.generateKeyPair();

        apple = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        apple.createContext("/", exchange -> {
            String path = exchange.getRequestURI().getPath();
            paths.add(path);
            forms.add(parse(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8)));
            byte[] body = "{\"refresh_token\":\"refresh-1\"}".getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(path.equals("/auth/token") ? tokenStatus : 200, body.length);
            exchange.getResponseBody().write(body);
            exchange.close();
        });
        apple.start();
    }

    @AfterEach
    void stopApple() {
        apple.stop(0);
    }

    private HttpAppleTokenRevoker revoker() {
        String pem = "-----BEGIN PRIVATE KEY-----\n"
                + Base64.getMimeEncoder().encodeToString(key.getPrivate().getEncoded())
                + "\n-----END PRIVATE KEY-----";
        return new HttpAppleTokenRevoker(new AppleRevocationProperties("TEAM", "KEY", pem,
                "http://127.0.0.1:" + apple.getAddress().getPort()));
    }

    @Test
    void exchangesTheCodeThenRevokesTheRefreshToken() throws Exception {
        revoker().revoke("the-code", "com.example.CoachSync");

        assertThat(paths).containsExactly("/auth/token", "/auth/revoke");
        assertThat(forms.get(0)).containsEntry("code", "the-code")
                .containsEntry("client_id", "com.example.CoachSync")
                .containsEntry("grant_type", "authorization_code");
        assertThat(forms.get(1)).containsEntry("token", "refresh-1")
                .containsEntry("token_type_hint", "refresh_token");

        SignedJWT secret = SignedJWT.parse(forms.get(1).get("client_secret"));
        assertThat(secret.verify(new ECDSAVerifier((ECPublicKey) key.getPublic()))).isTrue();
        assertThat(secret.getHeader().getKeyID()).isEqualTo("KEY");
        assertThat(secret.getJWTClaimsSet().getIssuer()).isEqualTo("TEAM");
        assertThat(secret.getJWTClaimsSet().getSubject()).isEqualTo("com.example.CoachSync");
        assertThat(secret.getJWTClaimsSet().getAudience()).containsExactly("https://appleid.apple.com");
    }

    @Test
    void anErrorFromAppleIsSwallowedAndNothingElseIsCalled() {
        tokenStatus = 400;

        assertThatCode(() -> revoker().revoke("bad-code", "com.example.CoachSync")).doesNotThrowAnyException();

        assertThat(paths).containsExactly("/auth/token");
    }

    @Test
    void withoutCredentialsItCallsNothing() {
        new HttpAppleTokenRevoker(new AppleRevocationProperties("", "", "",
                "http://127.0.0.1:" + apple.getAddress().getPort())).revoke("code", "com.example.CoachSync");

        assertThat(paths).isEmpty();
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
