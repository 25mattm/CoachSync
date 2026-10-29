/// Resolves where the CoachSync backend lives. Stage 1 of the app↔backend sync work.

import Foundation

/// The backend base URL. Reads the `CoachSyncBackendURL` Info.plist key when present
/// (so a scheme/build can point at a deployed backend), otherwise defaults to the local
/// dev backend on the simulator's host. Production will set the key to an HTTPS URL.
///
/// `Info.plist`'s `CoachSyncBackendURL` is committed as `http://localhost:8080` (there's no
/// per-configuration override anywhere in the Xcode project), so Release builds — TestFlight and
/// App Store included — use localhost until that key is set to the deployed HTTPS backend.
/// Debug builds ignore the key entirely and always use
/// `defaultBaseURL` — a developer pointing a Debug build at a real deployed backend can set the
/// `COACHSYNC_BACKEND_URL_OVERRIDE` environment variable on the run scheme instead.
// `nonisolated` (the module defaults to MainActor isolation): this is pure, thread-safe
// configuration — reading a string literal, ProcessInfo, and Bundle — with no UI state, so it
// must be reachable from the nonisolated default-argument expressions in `BackendClient.init`.
nonisolated enum BackendConfig {

    static let defaultBaseURL = URL(string: "http://localhost:8080")!

    static var baseURL: URL {
#if DEBUG
        if let raw = ProcessInfo.processInfo.environment["COACHSYNC_BACKEND_URL_OVERRIDE"],
           !raw.trimmingCharacters(in: .whitespaces).isEmpty,
           let url = URL(string: raw) {
            return url
        }
        return defaultBaseURL
#else
        if let raw = Bundle.main.object(forInfoDictionaryKey: "CoachSyncBackendURL") as? String,
           !raw.trimmingCharacters(in: .whitespaces).isEmpty,
           let url = URL(string: raw) {
            return url
        }
        return defaultBaseURL
#endif
    }
}
