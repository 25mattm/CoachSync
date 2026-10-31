# CoachSync — Developer Setup

Unified onboarding for the two halves of the project: the offline-first **iOS/Mac app**
(SwiftUI + SwiftData) and the **Spring Boot backend** (the shared club store the app syncs
through). You can work on either half independently — the app runs fully offline without the
backend.

For an overview of what each half is, read [`README.md`](README.md) (app) and
[`backend/README.md`](backend/README.md) (backend) first.

## Prerequisites

| For | Need |
|---|---|
| App | macOS + **Xcode** (current release), an iOS Simulator, an Apple Developer account for signing/TestFlight |
| Backend | **JDK 21+** (JDK 25 works; compiles to release 21). No global Maven — the repo ships `./mvnw`. MySQL only for a live run (tests use H2) |

## The app (iOS + macOS)

The Xcode project is `CoachSync.xcodeproj` with three targets — `CoachSync` (iOS),
`CoachSyncMac` (macOS), `CoachSyncTests` — and schemes `CoachSync` / `CoachSyncMac`.

Open it:

```bash
open CoachSync.xcodeproj
```

Then ⌘R to run or ⌘U to test, or from the command line:

```bash
# Build + run the unit tests on a simulator (iPhone 17 used in CI/dev):
xcodebuild test -project CoachSync.xcodeproj -scheme CoachSync \
  -destination 'platform=iOS Simulator,id=E36D2763'

# Build the macOS app:
xcodebuild build -project CoachSync.xcodeproj -scheme CoachSyncMac
```

> The simulator UUID above is one known-good device; substitute any installed iPhone simulator
> (`xcrun simctl list devices`) or use `-destination 'platform=iOS Simulator,name=iPhone 17'`.

The app is **offline-first** and needs no backend to run — it persists to SwiftData locally.
Cross-device/cross-Apple-ID club sharing goes through the CoachSync backend's Sign in with Apple +
sync engine (see below); CloudKit sync was retired in favor of it. Architecture and
where-to-read-first: [`README.md`](README.md).

### Pointing the app at the backend (optional)

Club-sync features talk to the backend. Debug builds always use `http://localhost:8080`, so run
the backend locally (below). Release builds read the Info.plist key **`CoachSyncBackendURL`**,
filled from `COACHSYNC_BACKEND_URL` (see the next section). Sign-in additionally requires the
coach's email to be in the backend allowlist — see [Authentication in backend/README](backend/README.md#authentication).

### Release builds: your bundle ID, team and backend

The repo ships public placeholders in `Config/Shared.xcconfig` (`com.example` bundle IDs, no
signing team, a localhost backend). They build, run and test as-is, but **archiving refuses
them**. Put your own values in a gitignored `Config/Local.xcconfig`:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Then set `COACHSYNC_BUNDLE_ID_PREFIX`, `COACHSYNC_DEVELOPMENT_TEAM` and an https
`COACHSYNC_BACKEND_URL` and `COACHSYNC_PRIVACY_POLICY_URL` in it. Every target and configuration picks them up.

## The backend

```bash
cd backend
./mvnw clean test            # full suite against in-memory H2 — no MySQL needed
```

A live run needs MySQL and serves on `:8080`; see **[`backend/README.md`](backend/README.md)**
for the run commands, a throwaway-MySQL recipe, the live Swagger UI / OpenAPI docs, and the
Spring Boot 4 contributor gotchas.

> Use `clean` and don't run `./mvnw` and an Xcode build at the same time — this repo is in an
> iCloud-synced directory where stale duplicate `.class` files can poison `target/`.

## Where things live

| Path | What |
|---|---|
| `CoachSync/` | iOS app sources (SwiftUI views, `Models.swift`, `SeasonContext.swift`, `Auth/`, `Sync/`, `Components/`) |
| `CoachSyncMac/` | macOS target (reuses the shared app views) |
| `CoachSyncTests/` | app unit tests |
| `backend/` | Spring Boot backend (see its README) |
| `docs/` | PRD, architecture notes, user guide |

### Account deletion: revoking the Sign in with Apple grant

Settings → Delete Account deletes the coach's account on the backend, as App Store Review Guideline
5.1.1(v) requires. To also revoke the Apple grant, which Apple requires of apps using Sign in with
Apple, give the backend a Sign in with Apple key from your Apple Developer account:

    COACHSYNC_APPLE_TEAM_ID, COACHSYNC_APPLE_KEY_ID, COACHSYNC_APPLE_PRIVATE_KEY

Keep these in your deployment's secrets, never in the repo. Without them the account is still
deleted, but the backend logs a warning and the grant isn't revoked.
