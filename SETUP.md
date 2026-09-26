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

Club-sync features talk to the backend. `BackendConfig` reads the base URL from the Info.plist
key **`CoachSyncBackendURL`** (dev default `http://localhost:8080`). Run the backend locally
(below), or set this key to a deployed HTTPS URL. Sign-in additionally requires the coach's
email to be in the backend allowlist — see [Authentication in backend/README](backend/README.md#authentication).

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
