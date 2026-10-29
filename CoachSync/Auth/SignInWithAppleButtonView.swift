/// Sign in with Apple button that drives the backend exchange through ``AuthManager``.
/// Cross-platform (iOS + macOS).

import SwiftUI
import AuthenticationServices

struct SignInWithAppleButtonView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            handle(result)
        }
        // A black button on a dark background loses its shape; Apple's guidelines call for
        // white there. The view's identity changes with the style so SwiftUI rebuilds the
        // underlying ASAuthorizationAppleIDButton, which can't restyle in place.
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .id(colorScheme)
        .frame(height: 44)
        .disabled(auth.isAuthenticating)
    }

    /// Extracts the identity token (a JWT) and the one-time full name from the Apple
    /// credential, then hands them to ``AuthManager`` for the backend exchange.
    private func handle(_ result: Result<ASAuthorization, Error>) {
        guard case let .success(authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            return
        }
        // Apple delivers the name only on the first authorization (never in the token).
        let displayName = credential.fullName.map {
            PersonNameComponentsFormatter().string(from: $0)
        }.flatMap { $0.isEmpty ? nil : $0 }

        Task { await auth.signIn(identityToken: identityToken, displayName: displayName) }
    }
}
