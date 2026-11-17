/// Confirms and performs in-app account deletion (App Store Review Guideline 5.1.1(v)).
/// Cross-platform (iOS + macOS).

import SwiftUI
import SwiftData
import AuthenticationServices
import OSLog

struct DeleteAccountSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private static let logger = Logger(subsystem: "CoachSync", category: "AccountDeletion")

    var body: some View {
        NavigationStack {
            Form {
                Section("What happens") {
                    Text("Your sign-in and personal details are permanently deleted, and this device is cleared.")
                    Text("Practices and notes you logged stay with your club, credited to “Former coach”. Athletes and teams belong to the club and aren't deleted.")
                    Text("This can't be undone. Signing in again later starts a new account that needs approval to join a club.")
                }
                Section {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = []
                    } onCompletion: { result in
                        handle(result)
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .id(colorScheme)
                    .frame(height: 44)
                    .disabled(isDeleting)
                    .accessibilityHint("Confirms with Apple, then permanently deletes your account")
                    if isDeleting {
                        ProgressView("Deleting your account…")
                    }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(Color.readableRed)
                    }
                } footer: {
                    Text("To confirm it's you, continue with Apple. Your account is deleted straight after.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Delete Account")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isDeleting)
                }
            }
        }
        .interactiveDismissDisabled(isDeleting)
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        guard case let .success(authorization) = result else { return }   // Canceling isn't an error.
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let codeData = credential.authorizationCode,
              let code = String(data: codeData, encoding: .utf8),
              let clientId = Bundle.main.bundleIdentifier else {
            errorMessage = "Apple didn't confirm it's you, so your account wasn't deleted. Please try again."
            return
        }
        isDeleting = true
        errorMessage = nil
        Task {
            defer { isDeleting = false }
            if let failure = await auth.deleteAccount(authorizationCode: code, clientId: clientId) {
                errorMessage = failure
                return
            }
            do {
                try LocalWipe.wipeAll(in: modelContext)
            } catch {
                // The account is already gone server-side, and signing out has blocked further
                // sync; the next club check wipes this device if this one couldn't.
                Self.logger.error("Local wipe after account deletion failed: \(error.localizedDescription)")
            }
            dismiss()
        }
    }
}
