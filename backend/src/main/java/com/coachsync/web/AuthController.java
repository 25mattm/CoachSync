package com.coachsync.web;

import com.coachsync.auth.AuthService;
import com.coachsync.web.dto.AppleSignInRequest;
import com.coachsync.web.dto.AuthResponse;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Public auth endpoints (permitted by {@code SecurityConfig}). {@code POST /api/auth/apple}
 * exchanges an Apple identity token for a backend session token, creating or linking the
 * coach on first sign-in.
 */
@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    @PostMapping("/apple")
    public AuthResponse signInWithApple(@Valid @RequestBody AppleSignInRequest request) {
        return authService.signInWithApple(request);
    }
}
