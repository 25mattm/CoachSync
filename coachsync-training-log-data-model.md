# CoachSync Backend — Training-Log Vertical
## Data Model Spec (hand-off for implementation)

### Context
First vertical of a club-wide, multi-coach Spring Boot backend (Java 21, Spring Web, Spring Data JPA, MySQL, Maven) that becomes the club's source of truth. This vertical covers the daily training log. Competition/results and assessments are later verticals. The existing SwiftUI/SwiftData app stays on CloudKit for now; UUID keys and a clean REST surface keep a future app-as-client migration open without committing to it.

### Conventions (all entities)
- **Primary key:** `@Id UUID id` — app-supplied on records originating in the app, or `UUID.randomUUID()` for records created server-side. Not `@GeneratedValue`/auto-increment. The backend should enforce PK uniqueness — CloudKit could not.
- **Enums:** `@Enumerated(EnumType.STRING)`. Stored value is the Java constant name (e.g. `PADDLE_DISTANCE`). The app stores display strings ("Paddle Distance"); a future import maps those to these constants.
- **Relationships:** owning side is `@ManyToOne` + `@JoinColumn` (FK on the child); inverse is `@OneToMany(mappedBy = …)`.
- **Times/durations:** integer **milliseconds** (`Integer`), matching the app's `recordedTimeMs`.
- **Timestamps:** `createdAt` as `Instant`; calendar dates as `LocalDate`; clock date-times as `LocalDateTime`.
- **Long free text:** `@Lob`.

### Entities

**Coach**

| field | type | notes |
|---|---|---|
| id | UUID | PK |
| name | String | not null |
| role | String | nullable |
| nccpLevel | String | nullable |
| colorHex | String | nullable |
| createdAt | Instant | |

Auth identity will attach here in the auth vertical.

**Athlete** (shared core — also used by later verticals)

| field | type | notes |
|---|---|---|
| id | UUID | PK |
| firstName | String | not null |
| lastName | String | not null |
| dateOfBirth | LocalDate | not null; source of truth for age |
| gender | Gender | nullable |
| guardianName | String | nullable |
| guardianPhone | String | nullable |
| guardianEmail | String | nullable |
| isActive | boolean | default true |
| developmentStage | DevelopmentStage | default INITIATION |
| createdAt | Instant | |

`ageCategory` is **not stored** — derive it from `dateOfBirth`. Children in this vertical: TeamMembership, AttendanceRecord, PerformanceRecord, AthleteNote.

**Team**

| field | type | notes |
|---|---|---|
| id | UUID | PK |
| teamName | String | not null |
| teamDescription | String | nullable |
| isArchived | boolean | default false |
| createdAt | Instant | |

Relationships: `@OneToMany memberships`, `@OneToMany sessions`. On team delete, **sessions are retained** (`team` set null) — do not cascade-delete sessions.

**TeamMembership** (athlete ↔ team join, date-ranged)

| field | type | notes |
|---|---|---|
| id | UUID | PK |
| athlete | Athlete | `@ManyToOne`, not null |
| team | Team | `@ManyToOne`, not null |
| joinedDate | LocalDate | not null |
| leftDate | LocalDate | nullable; null ⇒ active |

No hard unique on (athlete, team) — rejoining is allowed.

**CoachSession**

| field | type | notes |
|---|---|---|
| id | UUID | PK |
| sessionName | String | not null |
| scheduledDate | LocalDate | not null |
| startTime | LocalDateTime | nullable |
| endTime | LocalDateTime | nullable |
| status | SessionStatus | default OPEN |
| weatherNote | String | nullable |
| teamNote | String | nullable |
| sessionNote | String | nullable, `@Lob` |
| mfCue | String | nullable |
| isArchived | boolean | default false |
| createdAt | Instant | |
| coach | Coach | `@ManyToOne`, nullable — replaces `createdByCoachName` |
| team | Team | `@ManyToOne`, nullable |

Relationships: `@OneToMany sessionBlocks`, `attendanceRecords`, `athleteNotes`. The app's `scheduledDate`/`startTime`/`endTime` are all SwiftData `Date`s; split here into a day + clock times — adjust if you'd rather keep all three as full timestamps.

**SessionBlock**

| field | type | notes |
|---|---|---|
| id | UUID | PK |
| blockName | String | not null |
| blockType | BlockType | default PADDLE_DISTANCE |
| sortOrder | int | default 0 |
| repetitionCount | int | default 1 — governs per-athlete slot count |
| setCount | int | default 1 — descriptive (see open items) |
| targetDistanceMetres | Double | nullable |
| distanceKm | Double | nullable |
| restIntervalSeconds | Integer | nullable |
| durationSeconds | Integer | nullable |
| requiresTimeEntry | boolean | default true |
| trainingZone | TrainingZone | nullable |
| drillName | String | nullable |
| coachNote | String | nullable |
| prescribedRepDurationsSec | List\<Integer\> | `@ElementCollection` + `@OrderColumn` (ordered, may be empty) |
| session | CoachSession | `@ManyToOne`, not null |

Relationships: `@OneToMany performanceRecords`, `athleteNotes`. The distance fields overlap; ported as-is to stay aligned with the app.

**AttendanceRecord**

| field | type | notes |
|---|---|---|
| id | UUID | PK |
| status | AttendanceStatus | default PRESENT |
| absenceReason | String | nullable |
| session | CoachSession | `@ManyToOne`, not null |
| athlete | Athlete | `@ManyToOne`, not null |

**Unique (session, athlete).**

**PerformanceRecord**

| field | type | notes |
|---|---|---|
| id | UUID | PK |
| repNumber | int | not null; 1..repetitionCount |
| recordedTimeMs | Integer | nullable; milliseconds |
| status | RepEntryStatus | default PENDING |
| createdAt | Instant | |
| sessionBlock | SessionBlock | `@ManyToOne`, not null |
| athlete | Athlete | `@ManyToOne`, not null |

**Unique (sessionBlock, athlete, repNumber).** Backend pre-generates one row per **present** athlete × rep when a block's slots are created. Attendance is the input snapshot — there is **no** FK from PerformanceRecord to AttendanceRecord, so late arrivals and changed minds don't break integrity (reconciliation is endpoint logic).

**AthleteNote**

| field | type | notes |
|---|---|---|
| id | UUID | PK |
| noteText | String | not null, `@Lob` |
| createdAt | Instant | |
| athlete | Athlete | `@ManyToOne`, not null |
| session | CoachSession | `@ManyToOne`, not null |
| sessionBlock | SessionBlock | `@ManyToOne`, nullable (extra context) |
| coach | Coach | `@ManyToOne`, nullable — replaces `createdByCoachName` |

The app declares athlete/session optional but always sets them; relax to nullable if you want athlete-only notes.

### Enums (`EnumType.STRING`)
- **SessionStatus:** OPEN, COMPLETED, CANCELLED
- **RepEntryStatus:** PENDING, COMPLETE, DNS, DNF
- **AttendanceStatus:** PRESENT, ABSENT, EXCUSED
- **Gender:** MALE, FEMALE
- **DevelopmentStage:** INITIATION, ACQUISITION, CONSOLIDATION, REFINEMENT
- **TrainingZone:** GA_1, GA_2, E_1, E_2, AN_MIX, ALACTIC, RECOVERY
- **BlockType:** PADDLE_DISTANCE, PADDLE_TIME_PIECES, PADDLE_PYRAMID, RUN_DISTANCE, RUN_INTERVALS, WEIGHTS, CIRCUIT, CORE, TECHNIQUE

### Delete behavior
The app hand-rolls cascades (CloudKit forbade them); here use JPA `cascade` + `orphanRemoval` or DB FKs, mirroring the app's intent:
- Athlete delete → cascade its children.
- CoachSession delete → cascade blocks, attendance, notes (and performance records via blocks).
- **Team delete → nullify sessions** (sessions retained), cascade memberships only.

### Open items — resolve before the slot-generation endpoint (logic, not schema)
1. Does `setCount` multiply the per-athlete slot count, or is it descriptive metadata?
2. Do block types that don't capture per-rep data (Core, Technique, Weights…) get PerformanceRecord slots, or only timed types (the app's `BlockType.capturesPerRepData` / `requiresTimeEntry`)?

Neither changes the entity definitions — they shape the generation endpoint only.
