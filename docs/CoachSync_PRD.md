# CoachSync Product Requirements

## Product Summary
CoachSync is an offline-first coaching app for competitive paddling coaches. It supports the full day-to-day coaching workflow: managing athletes and teams, planning and logging training sessions, tracking individual performance over time, running regatta results, and reviewing long-term athlete development — all without requiring network connectivity.

The app centers on a single coach's workflow, with multiple coach profiles within a club (v1.2).
Original cross-device sync used CloudKit (v1.1, one iCloud account only); CloudKit was later
retired in favor of a CoachSync backend + Sign in with Apple sync engine, which additionally
supports cross-Apple-ID club sharing — built and tested, not yet in a shipped release.

---

## Business Rules (Non-Negotiable)

### Age Categories
- Age = current calendar year minus birth year (not a cutoff date)
- Minimum age enforced at 5 — below 5 returns "N/A"
- Category mapping: U10 (5–10), U12 (11–12), U14 (13–14), U16 (15–16), U18 (17–18), Senior (19+)
- `SeasonContext` is the single source of truth for all age category logic — never duplicated in models or views

### Data Integrity
- **Athletes with recorded practice history cannot be deleted.** They must be marked inactive instead. "History" means data the coach actually recorded — present attendance, timed/DNS/DNF results, notes, tests, regattas, assessments, heights. Roster-tracking artifacts (absent/excused-only attendance, never-filled pending rep slots) do **not** lock an athlete, so a kid rostered once who never attended stays deletable.
- **Completed sessions cannot be deleted.** Coaches use Settings → "Archive Completed Practices" to retire them; archiving groups into one `SeasonArchive` snapshot per season year, so prior-year leftovers archive under their own year.
- **DOB picker is always bounded to `...Date.now`** — future birth dates are never accepted.

### Session Lifecycle
- States: Open → Completed (or Cancelled)
- A session stays Open until the coach marks it Completed or Cancelled; the Dashboard buckets open sessions by date
- Completed and Cancelled sessions are terminal; completed sessions are preserved permanently
- Archived sessions are hidden from Dashboard and Schedule but performance data remains fully queryable

### Training Load
- Recovery zone km (TrainingZone.recovery) is **excluded** from all training load calculations
- Load is computed from `SessionBlock.effectiveDistanceKm` (uses `distanceKm` if set, otherwise calculates from repetitionCount × targetDistanceMetres)
- **Athlete load counts completed sessions only** (matching team load) — open or cancelled practices never feed totals, and sessions are deduplicated by id so synced duplicate attendance can't double-count km
- **LTAD progress counts paddling km only** (paddle block types) — run km counts toward headline weekly/season totals but does not advance the CKC on-water target bar

---

## Feature Status

| Feature | Status | Notes |
|---|---|---|
| Athlete management (CRUD, search, deactivate) | Shipped | Deletion guard checks full history |
| Athlete sort by age / name / sex | Shipped | Age grouping uses SeasonContext category order |
| Team management (CRUD, archive) | Shipped | Roster via TeamMembership (leftDate soft-remove) |
| Team seasonal load + zone breakdown | Shipped | Recovery excluded; weekly + seasonal km |
| Session scheduling and editing | Shipped | EditSessionSheet; does not touch block data |
| Session lifecycle (Open → Completed) | Shipped | Open until marked Completed/Cancelled |
| Session deletion guards | Shipped | Completed sessions blocked; alert directs to archive |
| Attendance logging | Shipped | Present / Absent / Excused; bulk shortcuts |
| Performance logging (timed reps) | Shipped | DNS / DNF supported; TimeParsing for all input |
| 9 block types | Shipped | Paddle Distance/Time Pieces/Pyramid, Run Distance/Intervals, Weights, Circuit, Core, Technique |
| 7 training zones | Shipped | GA1, GA2, E1, E2, AN Mix, Alactic, Recovery |
| Regatta results | Shipped | Placement, time, competitor count; swipe edit/delete |
| Calendar view with session + regatta dots | Shipped | Blue dots = sessions; orange dots = regatta results |
| Athlete profile (4-tab) | Shipped | Overview / Performance / Development / Notes |
| Athlete insight signals (profile-level) | Shipped | Declining, inconsistent pacing, most improved |
| Needs Attention dashboard section | Shipped | Up to 5 athletes with negative signals |
| Technical assessments | Shipped | Stage snapshot, 1–5 factor ratings, DevelopmentFocusPanel |
| Fitness testing (CKC benchmarks) | Shipped | 9 physical + 7 on-water tests; LTAD benchmarks; quarterly banner |
| PHV height tracking | Shipped | Annualized velocity; flag ≥ 6 cm/year |
| Development journal | Shipped | DevelopmentNote with 10 predefined tags |
| Training load display (athlete + team) | Shipped | Weekly/seasonal km; zone breakdown |
| Season archiving | Shipped | Marks sessions isArchived; records SeasonArchive snapshot |
| CSV athlete import | Shipped | Bulk import via CSVImportView |
| Age category reference in Settings | Shipped | Birth-year rules per category for current season |
| CloudKit cross-device sync | Shipped | Automatic iPhone ↔ Mac sync (one Apple ID) via SwiftData + CloudKit (v1.1) |
| Coach profiles + first-launch onboarding | Shipped | `Coach` model; club+coach setup via `OnboardingGate`; Settings → Coaches editor; per-device coach via `CoachIdentity` (v1.2) |
| "Logged by" attribution | Shipped | `createdByCoachName` stamped on sessions/notes, shown via `LoggedByLabel` (v1.2) |
| PB display during live block entry | Deferred | PerformanceRecord exists; UI not surfaced in logger |

---

## Explicitly Deferred

These items are intentionally out of scope unless explicitly re-prioritized.

### Product / Platform
- Multi-coach collaboration across **separate Apple IDs** (coach profiles within one shared club iCloud account shipped in v1.2)
- Multi-user permissions or role-based access
- Cross-Apple-ID sync (single-account multi-device sync shipped in v1.1)
- Parent or athlete portals
- Notifications and reminders
- Export workflows beyond what is strictly necessary

### Architecture / Implementation
- Broad file splits or large refactors unless explicitly requested
- New shared helpers or components unless clearly justified
- Regression math extraction (linear regression logic currently duplicated in two locations — acceptable until a third location would require it)
- Idealized architecture changes that increase risk without immediate user value

---

## Product Principles
- Prefer safe, incremental progress over ambitious rewrites
- Preserve offline-first behavior
- Keep coaching intelligence explainable and coach-readable
- Match the existing visual style and card patterns
- Treat data trust as more important than feature breadth
- Single-account assumptions are preserved (one coach's own devices, or a club sharing one iCloud account); cross-Apple-ID collaboration stays out of scope until explicitly instructed
