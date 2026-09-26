# CoachSync Architecture Notes

## Stack and Constraints
- **Language / UI:** Swift, SwiftUI
- **Persistence:** SwiftData (file-based store at `~/.appSupport/CoachSync/CoachSync.store`; in-memory fallback on store failure)
- **Platform:** iOS + macOS via conditional `#if os(iOS)` / `#if os(macOS)` guards for platform-specific UI only; shared logic must not fork by platform
- **Connectivity:** Offline-first — core workflows require zero network connectivity
- **Scale:** Single coach's workflow, with coach profiles within a club (v1.2). Cross-device sync originally used CloudKit (v1.1, one iCloud account); CloudKit was retired in Phase 2 in favor of a CoachSync backend + Sign in with Apple sync engine, which also supports cross-Apple-ID club sharing — built and tested, not yet in a shipped release

---

## File Structure

| File | Purpose |
|---|---|
| `CoachSyncApp.swift` | App entry point; SwiftData container initialization with file-based + in-memory fallback |
| `ContentView.swift` | 5-tab root navigation (Home / Athletes / Teams / Schedule / Settings) |
| `OnboardingView.swift` | First-launch club+coach setup; hosts `OnboardingGate`, `CoachIdentity` (device-local current coach), `LoggedByLabel`, `CoachFormFields` (v1.2) |
| `Models.swift` | All 17 SwiftData @Model classes and all enums — single source for schema |
| `SeasonContext.swift` | Static utility: age category logic, season-year calculations, session filtering, load km |
| `TimeParsing.swift` | All ms↔display-string conversions; all time parsing — nothing inlined in views |
| `DashboardView.swift` | Today's sessions, upcoming, recent completed, NeedsAttentionSection |
| `AthletesView.swift` | Roster grouped by age category; sort by age/name/sex; search; deletion guards |
| `AthleteProfileView.swift` | 4-tab athlete profile: Overview / Performance / Development / Notes |
| `TeamsView.swift` | Team CRUD, archive, roster management, seasonal load and zone breakdown |
| `ScheduleView.swift` | Monthly calendar grid, session and regatta dots, session CRUD entry points |
| `SessionLoggerView.swift` | 3-phase logger: attendance → block entry → session summary |
| `SettingsView.swift` | Club info, age category reference, CSV import, season archiving, data reset |
| `EditSessionSheet.swift` | Session metadata editor (name, date, times, team); does not modify block/performance data |
| `Components/CategoryPill.swift` | Age category capsule with semantic color |
| `Components/StatusPill.swift` | Session status badge (visible only for completed/cancelled) |
| `Components/EmptyCard.swift` | Reusable empty state: icon + message |
| `Components/SectionHeader.swift` | Bold section title for scroll layouts |
| `Components/Color+AgeCategory.swift` | `Color.ageCategory(_ category: String)` extension |

---

## Data Model

### @Model Classes

**Athlete**
- Fields: `id`, `firstName`, `lastName`, `dateOfBirth`, `gender` (Gender?), guardian contact fields (optional), `isActive`, `developmentStage`, `createdAt`, `updatedAt`
- Cascade relationships: memberships, attendanceRecords, performanceRecords, notes, fitnessTestResults, regattaResults, technicalAssessments, heightRecords, developmentNotes
- Computed: `fullName`, `ageCategory` (delegates to `SeasonContext.ageCategory(for:)`)

**Team**
- Fields: `id`, `teamName`, `teamDescription` (optional), `isArchived`, `createdAt`
- Cascade: memberships; **nullify** on sessions (preserves session history if team is deleted)
- Computed: `activeMembers` (memberships where leftDate == nil)

**TeamMembership**
- Fields: `id`, `joinedDate`, `leftDate` (nil = still active)
- Relationships: `athlete: Athlete?`, `team: Team?`
- Soft-remove pattern: set `leftDate = Date()` rather than deleting the record

**CoachSession**
- Fields: `id`, `sessionName`, `scheduledDate`, `startTime/endTime`, `actualStartTime/actualEndTime` (optional), `status` (SessionStatus), `weatherNote`, `teamNote`, `isArchived`, `createdAt`, `updatedAt`, `createdByCoachName` (optional — "logged by" attribution, v1.2)
- Cascade: sessionBlocks, attendanceRecords, athleteNotes
- isArchived = true hides from Dashboard and Schedule but preserves all data

**SessionBlock**
- Fields: `id`, `blockName`, `blockType` (BlockType), `sortOrder`, `repetitionCount`, `targetDistanceMetres` (optional), `coachNote`, `trainingZone` (TrainingZone?), `distanceKm` (optional)
- Cascade: performanceRecords, athleteNotes
- Computed: `effectiveDistanceKm` — uses `distanceKm` if set; otherwise `(repetitionCount × targetDistanceMetres) / 1000.0`

**AttendanceRecord**
- Fields: `id`, `status` (AttendanceStatus), `absenceReason` (optional)
- Relationships: `session: CoachSession?`, `athlete: Athlete?`

**PerformanceRecord**
- Fields: `id`, `repNumber`, `recordedTimeMs` (Int?), `isDNS`, `isDNF`, `createdAt`, `updatedAt`
- Relationships: `sessionBlock: SessionBlock?`, `athlete: Athlete?`
- Computed: `formattedTime` — "DNS" / "DNF" / `formatMillisecondsForDisplay(ms)`

**AthleteNote**
- Fields: `id`, `noteText`, `createdAt`, `createdByCoachName` (optional, v1.2)
- Relationships: `session: CoachSession?`, `sessionBlock: SessionBlock?` (optional), `athlete: Athlete?`

**TechnicalAssessment**
- Fields: `id`, `date`, `stage` (DevelopmentStage), `overallNotes` (optional), `createdAt`
- Cascade: ratings
- Computed: `averageScore` (mean of all TechnicalRating.score values)

**TechnicalRating**
- Fields: `id`, `category`, `factor`, `score` (clamped 1–5), `comment` (optional)
- Relationships: `assessment: TechnicalAssessment?`

**RegattaResult**
- Fields: `id`, `regattaName`, `location` (optional), `regattaDate`, `eventDistance` (Int), `placement/totalCompetitors` (optional), `resultTimeMs`, `notes` (optional), `createdAt`
- Relationships: `athlete: Athlete?`
- Computed: `formattedTime` — `formatMillisecondsForDisplay(resultTimeMs)`

**FitnessTestResult**
- Fields: `id`, `testType`, `result` (Double), `unit` (String), `testDate`, `notes` (optional), `createdAt`
- Relationships: `athlete: Athlete?`

**DevelopmentNote**
- Fields: `id`, `date`, `text`, `tags: [String]`, `createdAt`, `createdByCoachName` (optional, v1.2)
- Relationships: `athlete: Athlete?`
- Free-form coaching journal entry; 10 predefined tag options in UI

**HeightRecord**
- Fields: `id`, `heightCm` (Double), `date`, `createdAt`
- Relationships: `athlete: Athlete?`
- Used for PHV velocity calculation (cm/year)

**KTCAssessment**
- Fields: `id`, `date`, `window`, `setupRecoveryScore`, `catchScore`, `propulsionDrawScore`, `exitScore` (each clamped 1–5), `notes` (optional), `createdAt`
- Relationships: `athlete: Athlete?`
- CKC Kayak Technical Check snapshot; `averageScore` is the mean of the four phase scores

**SeasonArchive**
- Fields: `id`, `seasonYear`, `archiveDate`, `totalAthletes`, `totalSessions`, `totalKm`, `notes` (optional)
- Created when season is archived via SettingsView

**Coach** (v1.2)
- Fields: `id`, `name`, `role` (optional), `nccpLevel` (optional), `colorHex` (optional, auto-assigned from a fixed palette), `createdAt`
- **No relationships** — coaches are referenced by a `createdByCoachName` String snapshot on `CoachSession` / `AthleteNote` / `DevelopmentNote`, not a hard relationship, so attribution survives profile edits/renames. All stored properties optional or defaulted for CloudKit safety
- Computed: `initials`, `displayColor` (`Color(hex:)` with `.accentColor` fallback)
- The device's *active* coach is tracked separately by `CoachIdentity` (UserDefaults), not on the model; `currentName(in:)` resolves the live name by stable ID

### Enums

| Enum | Cases |
|---|---|
| BlockType | paddleDistance, paddleTimePieces, paddlePyramid, runDistance, runIntervals, weights, circuit, core, technique |
| RepEntryStatus | pending, complete, dns, dnf |
| SessionStatus | open, completed, cancelled |
| AttendanceStatus | present, absent, excused |
| Gender | male, female |
| TrainingZone | ga1 (70–80%), ga2 (80–85%), e1 (85–95%), e2 (95–100%), anMix (Max HR), alactic (Alactic Speed), recovery (<65%) |
| DevelopmentStage | initiation, acquisition, consolidation, refinement |

`TrainingZone` embeds a `color: Color` and HR description per case. `SessionStatus.color` returns `.clear` for open, `.gray` for completed, `.red` for cancelled.

---

## Key Architectural Patterns

### SeasonContext as Single Source of Truth
`SeasonContext.swift` is a static enum. All age category logic, season-year calculations, session filtering, and load km computation live here. `Athlete.ageCategory` is a computed property that delegates to `SeasonContext.ageCategory(for:)`. No view or model may duplicate this logic.

### TimeParsing Ownership
`TimeParsing.swift` owns all millisecond↔display-string conversions. Views never format or parse times inline. `PerformanceRecord.formattedTime` calls `formatMillisecondsForDisplay`; views call `TimeParsing.parseTimeToMs()` for input.

### Soft-Delete Patterns
- **Sessions:** `isArchived = true` removes from Dashboard/Schedule queries; data is fully preserved
- **Teams:** `isArchived = true` hides from active team list
- **Memberships:** `leftDate = Date()` ends active membership without deleting the record
- **Athletes:** `isActive = false` deactivates; direct deletion is only allowed when the athlete has zero history

### Cascade vs Nullify
- **Cascade (most relationships):** Deleting an Athlete removes all their history atomically. Deleting a Session removes its blocks, attendance, and notes.
- **Nullify (Team → Sessions):** Deleting or archiving a Team preserves session history; sessions retain their team reference as nil.

### Phase-Driven Modal Flows
`SessionLoggerView` uses a `LoggerPhase` enum (attendance → blockEntry → summary) to drive a three-step modal. In-memory state (`attendanceMap: [UUID: AttendanceStatus]`, `timeEntries`) is held in `@State` and flushed to SwiftData on phase advance. Errors surface via alert; state is preserved for retry.

### Season-Aware Queries
Dashboard, TeamDetailView, and SettingsView filter sessions using `SeasonContext.dateInterval(forYear:)`. The interval uses an exclusive end boundary (`date < interval.end`) to prevent Jan 1 of the next year from leaking into the current season.

### Insight Signal Computation
Linear regression slope and coefficient-of-variation pacing are computed inline in two locations:
- `AthleteInsightSection` in `AthleteProfileView.swift` (profile-level; three signals)
- `NeedsAttentionSection` in `DashboardView.swift` (dashboard-level; two negative signals only)

This duplication is intentional. Extract only if a third location requires the same logic.

### DateFormatter in ScheduleView
`dayKeyFormatter` is a file-level static (`static let`) in `ScheduleView.swift`. No per-render `DateFormatter` instances are created in calendar rendering code.

---

## Business Rule Implementation Map

| Rule | Implemented In |
|---|---|
| Age = season year − birth year | `SeasonContext.athleteAge(for:inYear:)` |
| Age categories (U10–U18, Senior, N/A) | `SeasonContext.ageCategory(for:inYear:)` |
| Minimum age 5 → "N/A" | `SeasonContext.ageCategory` guard |
| DOB bounded to ...Date.now | `AddAthleteSheet` DatePicker |
| Athlete deletion guard | `AthletesView.hasPracticeHistory()` |
| Completed session deletion guard | `ScheduleView` swipe-delete check on `session.status` |
| Recovery zone excluded from load | `SeasonContext.loadKilometers(from:)` filters `.recovery` |
| Scheduled → In Progress on logger open | `SessionLoggerView` `onAppear` transition |
| Completed sessions archived not deleted | `SettingsView` archive flow sets `isArchived = true` |
| SeasonArchive snapshot on archive | `SettingsView` archive action creates `SeasonArchive` record |

---

## Known Technical Debt

- **Regression math duplication:** Linear regression (slope) and CV pacing logic are duplicated in `AthleteInsightSection` and `NeedsAttentionSection`. Leave in place — extract only when a third callsite exists.
- **PB during live entry:** `PerformanceRecord` has no live personal-best display inside the block logger. Deferred pending UX decision on how to surface it without cluttering time entry.

---

## Constraint Checklist for AI Helpers

- All SwiftData models must live in `Models.swift`
- `TimeParsing.swift` owns all ms↔string conversions — never inline time formatting in views
- `SeasonContext` is the single source for age/season logic — never duplicate in views or models
- `dayKeyFormatter` in `ScheduleView.swift` is a file-level static — no per-render DateFormatter instances
- Cross-platform UI differences use `#if os(iOS)` / `#if os(macOS)` guards only; shared logic must not fork
- Prefer the safest implementation over ideal architecture
- Avoid broad refactors unless explicitly requested
- Prefer one-file or minimal-file changes when possible
- Reuse existing logic and UI patterns before introducing new helpers
- Do not introduce new shared helpers/components unless clearly justified
- Keep coaching intelligence compact, explainable, and coach-readable
- Ground suggestions in the actual codebase, not generic best practices alone
- Avoid touching unrelated files unless necessary
- Do not modify PRD / architecture documents unless explicitly asked
