# CoachSync User Guide

*Version 1.0 (Beta) — May 2026*

CoachSync is an offline-first iPhone and Mac app for competitive paddling coaches. Track athletes across a full season, log practices, capture performance times, run technical and fitness assessments, and surface coaching insights — all without an internet connection.

This guide walks through everything the app can do today. Skim the **Quick Start** if you're impatient, or read straight through if you want the full tour.

---

## Contents

- [Quick Start](#quick-start)
- [The Five Tabs](#the-five-tabs)
- [Setting Up Your Squad](#setting-up-your-squad)
- [Daily Coaching Workflow](#daily-coaching-workflow)
- [Block Types and Training Zones](#block-types-and-training-zones)
- [Athlete Profiles](#athlete-profiles)
- [Development Tracking](#development-tracking)
- [Regattas](#regattas)
- [Coaching Intelligence](#coaching-intelligence)
- [Season Operations](#season-operations)
- [Tips, Gotchas, and FAQs](#tips-gotchas-and-faqs)
- [Beta Tester Notes](#beta-tester-notes)

---

## Quick Start

1. **Install** from your TestFlight invite link.
2. **Open Settings → Club Info** and enter your club name.
3. **Teams tab → Create First Team** — give it a name (e.g. "Senior K1 Squad").
4. **Athletes tab → +** — add at least one athlete (or use **Settings → Import Athletes from CSV** to bulk-load).
5. **Home tab → +** — create a practice: pick a date, the team, and add at least one block.
6. **Home tab → Log Practice** on today's session to take attendance, enter times, and complete the practice.
7. Tap an athlete's name anywhere to see their full profile.

That's the loop. The rest of this guide goes deeper.

---

## The Five Tabs

CoachSync has five top-level surfaces. On iPhone they're a bottom tab bar; on Mac they're the sidebar.

| Tab | Icon | What lives here |
|---|---|---|
| **Home** | house | Today's practices, what's next, recent practices, and **Needs Attention** signals |
| **Athletes** | person.2 | The athlete roster (search, sort, filter by team, edit profiles) |
| **Teams** | person.3 | Team roster management, archive teams, view per-team training load |
| **Schedule** | calendar | Month calendar with practice dots (blue) and regatta dots (orange) |
| **Settings** | gear | Club info, season management, CSV import, data reset, age category reference |

---

## Setting Up Your Squad

### Add your club name

**Settings → Club Info** — type your club name into the field. It appears throughout the app (dashboard header, archived season summaries, etc.).

### Create a team

**Teams tab**. If you have none, the empty state says *"Create a team and add athletes to start logging practices."* Tap **Create First Team**. Give it a name and an optional description. You can have multiple teams (squad groups, training cohorts, regatta teams).

### Add athletes one at a time

**Athletes tab → +**. Enter:
- **First name, Last name, Date of Birth, Sex (M/F)**
- Optional: **Guardian name, phone, email** (for athletes who are minors)
- Optional: **Development stage** — one of Initiation, Acquisition, Consolidation, or Refinement

Save. The athlete appears in the roster. Tap their name to open their profile.

### Bulk import via CSV

**Settings → Import Athletes from CSV**. The import flow has three steps:
1. **Ready** — tap to pick a CSV file (Files app, iCloud Drive, etc.).
2. **Preview** — CoachSync shows parsed athletes and any rows with errors. Fix the CSV and re-import if needed.
3. **Done** — confirmation summary with import count.

Required CSV columns: `FirstName`, `LastName`, `DateOfBirth`. Optional: `Gender`, `GuardianName`, `GuardianPhone`, `GuardianEmail`. Column names are case-sensitive CamelCase. Date format: `MM/DD/YYYY`.

### Add athletes to a team

Open the team in the **Teams tab** → Roster section → tap **+** → check the athletes who belong to this team → Save. An athlete can be on multiple teams.

### Mark an athlete inactive (instead of deleting)

If an athlete moves on, **don't delete** them if they have practice history — that breaks the historical records. Instead, open the athlete's profile → **Edit** → toggle **Active** off. Inactive athletes are hidden from session attendance lists and team rosters but their data is preserved.

Athletes with zero practice history *can* be deleted outright.

---

## Daily Coaching Workflow

### 1. Schedule a practice

Two entry points: **Home tab → +** or **Schedule tab → Add Practice**.

Both open the same Add Practice sheet:
- **Session name** (e.g. "Tuesday AM Long Paddle")
- **Date and time**
- **Team** (or skip for an open practice — but team is recommended so attendance is pre-populated)
- **MF Cue (optional)** — a one-line mental-focus cue for the session
- **Blocks** — tap **+ Add Block** to attach as many as you want (see Block Types below)

Save. The practice now appears on the Home dashboard, on the Schedule calendar (blue dot), and in the team's session history.

### 2. Run the practice

When practice time comes around, find the session on the Home tab and tap **Log Practice**. This opens the Session Logger, which walks you through three phases:

**Phase A — Attendance.** All athletes assigned to the team appear. Tap each athlete to cycle through **Present → Absent → Excused**. The header shows the running count ("12 of 15 present"). Shortcuts at the top: **Mark All Present**, **Mark All Absent**. Tap **Next** when done.

**Phase B — Block-by-block entry.** Each block becomes its own screen. The progress indicator at the top shows "Block 2 of 5".

- **For tracked blocks** (Paddle Distance, Paddle Time Pieces, Paddle Pyramid, Run Distance, Run Intervals): you see a grid of present athletes with one or more time-entry fields per rep. Enter times as `M:SS.xx` (`1:23.4`), full seconds (`83.4`), `H:MM:SS.xx` for long pieces, or `DNS`/`DNF` for athletes who couldn't complete. Leave blank for pending — you can come back later. The athlete's personal best for this block name shows in green next to their row.
- **For checkpoint blocks** (Weights, Core, Circuit, Technique): you just see the block summary and a **Mark Complete** button. No per-athlete data is captured.

Keyboard shortcuts on Mac (and iPhone external keyboard): **Cmd+←** previous block, **Cmd+→** next block.

**Phase C — Summary.** Review attendance breakdown (Present/Absent/Excused/Total), total kilometres logged (recovery zone is excluded from totals on purpose — see Coaching Intelligence below), zone breakdown, and per-block recording status ("8/12 athletes logged"). Add **Practice Notes** if useful. Tap **Complete Practice** to mark the session done.

### 3. Edit a practice mid-flow

Inside the logger, the **…** menu offers **Edit Session** which opens the same sheet you used to create the practice. Add/remove blocks, change the time, fix the team. The **Done** button saves attendance and exits without marking the session complete — you can come back to it later.

### Session lifecycle

Practices move through these states:

- **Scheduled** — created but not started
- **In Progress** — opening the logger auto-transitions Scheduled → In Progress
- **Completed** — coach tapped Complete Practice
- **Cancelled** — coach explicitly cancelled

**Completed practices cannot be deleted.** This is intentional: completed sessions preserve athletes' performance history. If you need to clear them out at season's end, use **Season Archiving** (Settings → Season Management).

---

## Block Types and Training Zones

### Block types

Available in the Add Block sheet:

**On-water tracked:**
- **Paddle Distance** — reps × distance per rep, with auto-calculated total km. Requires a training zone.
- **Paddle Time Pieces** — reps × duration per rep. Toggle between time-tracked and check-off modes.
- **Paddle Pyramid** — drag-edit per-rep durations in seconds, grouped by sets. Default template: 4 sets × `[4', 2', 1', 30", 1', 2', 4']`.

**Land-based tracked:**
- **Run Distance** — like Paddle Distance but no training zone.
- **Run Intervals** — like Paddle Time Pieces but no training zone.

**Checkpoint (no per-athlete data):**
- **Weights** — duration + coach note.
- **Core** — duration + coach note.
- **Circuit** — duration + coach note.
- **Technique** — duration + coach note.

### Training zones (paddle blocks only)

CoachSync uses the standard 7-zone paddling model:

| Zone | What it is | Counts toward training load? |
|---|---|---|
| **Ga-1** | General Aerobic 1 (low intensity) | Yes |
| **Ga-2** | General Aerobic 2 | Yes |
| **E-1** | Endurance 1 | Yes |
| **E-2** | Endurance 2 (lactate threshold) | Yes |
| **AN Mix** | Anaerobic mixed | Yes |
| **Alactic** | Alactic / max-power sprints | Yes |
| **Recovery** | Active recovery | **No** (excluded from total) |

Recovery is excluded so it doesn't inflate weekly load numbers. It still appears in the zone breakdown so you can see how much recovery work an athlete is getting.

---

## Athlete Profiles

Tap any athlete name (from Athletes tab, team rosters, attendance lists, etc.) to open their profile. The profile has four tabs across the top:

### Overview tab

- **Athlete Insight Section** — surfaces active signals. Display format is `<block name>: <signal>`, lowercase. Examples: `Long Paddle: declining`, `6×500m: erratic pacing (12% CV)`, `500m TT: improving`. Border colour reflects status (green = positive only, orange = at least one negative signal active).
- **Team Memberships** — which teams the athlete is on right now and their join date.
- **Session History** — recent practices the athlete attended, status, and date.

### Performance tab

- **Performance Log Section** — best times by block name, with deltas from previous bests.
- **Regatta Results** — race results (date, location, event distance, time, placement).
- **Load Section** — weekly training volume in km, broken down by zone. Recovery is shown but excluded from the total.

### Development tab

- **Technical Summary** — current development stage and most recent technical-factor ratings.
- **Development Focus Panel** — automatically flags factor groups rated ≤2 (gaps) and ≥4 (strengths) from the most recent technical assessment.
- **Fitness Tests Summary** — latest on-water tests (2000m time trial, sprints) and CKC physical battery results (erg, vertical jump, 20m sprint, push-ups, etc.) with LTAD benchmarks.
- **Height & Growth** — height records over time with annualised growth rate. Flagged if growth rate is ≥6 cm/year (peak height velocity window).
- **KTC Scores** — Kayak Test Cycle composite scores.
- **Development Journal** — freeform tagged notes. 10 predefined tags: `catch`, `exit`, `draw`, `balance`, `boat-control`, `fitness`, `mental`, `race-prep`, `technique`, `goal`.

### Notes tab

- A single freeform notes section for anything that doesn't fit elsewhere.

### Editing the athlete

The **Edit** button (top right) opens the same sheet used during athlete creation. You can update name, DOB, sex, guardian info, development stage, and toggle Active/Inactive.

---

## Development Tracking

### Technical assessments

**Athlete profile → Development tab → Technical Assessments → New Assessment.**

1. Pick the assessment date.
2. Confirm the athlete's development stage (auto-filled from their profile but you can override).
3. For each factor group (Catch, Drive, Recovery, Posture, etc. — varies by stage), rate **1–5** with optional comments.
4. Add an overall coaching note.
5. Save.

The most recent assessment populates the **Development Focus Panel** (gaps ≤2 / strengths ≥4) shown on the Overview tab.

### Fitness tests

**Athlete profile → Development tab → Fitness Tests → New Result.**

Categories:
- **CKC Physical Battery (9 tests)** — erg 2km, vertical jump, 20m sprint, push-ups, pull-ups, broad jump, sit-and-reach, plank, medicine ball throw.
- **On-water tests (7 tests)** — 2000m time trial, 1000m TT, 500m TT, 200m TT, 6km steady, 8×500m, sprint sets.

Each test result captures the score and the test date. LTAD benchmark bands are shown next to each result for context — the best entry is compared against the benchmark for the athlete's age and stage.

### Height & PHV tracking

**Athlete profile → Development tab → Height & Growth → +**.

Enter the athlete's height (cm) and the date measured. The view shows the full history, the annualised growth rate, and flags peak height velocity windows where growth ≥6 cm/year — useful for adjusting training load around growth spurts.

### Development journal

**Athlete profile → Development tab → Development Journal → +**.

Quick tagged notes. Choose one of 10 predefined tags — `catch`, `exit`, `draw`, `balance`, `boat-control`, `fitness`, `mental`, `race-prep`, `technique`, `goal` — write the note, save. Notes are date-stamped and scannable from the athlete profile.

---

## Regattas

### Log a regatta result

**Athlete profile → Performance tab → Regatta Results → +**.

Or for batch entry: there's a global regatta entry from a per-regatta sheet that lets you record one regatta across the whole team at once.

Fields:
- Regatta name, location, date
- Event distance (200, 500, 1000, 2000, 6000m)
- Optional: filter by team
- Per-athlete: time and placement (1st, 2nd, 3rd…)

### View on the calendar

**Schedule tab** — orange dots mark regatta dates, blue dots mark practices. Tap a day to see what's on.

### Pull regatta history per athlete

**Athlete profile → Performance tab → Regatta Results.** All recorded results in reverse-chronological order.

---

## Coaching Intelligence

CoachSync watches your data and surfaces patterns. All intelligence is rule-based and explainable — no black-box ML.

### Needs Attention (Home tab)

Up to 5 athletes are surfaced at the top of the dashboard when they have active negative signals. Tap an athlete row to jump straight to their profile.

### Insight signals (per athlete, per block)

Signals are computed from the athlete's performance log. Each signal needs a minimum number of records before it fires. On screen they show as `<block name>: <signal>` (lowercase signal text).

- **declining** — linear regression slope > +50 ms over the last 3+ records for the same block name. (Positive slope = times getting slower = declining.)
- **erratic pacing** — coefficient of variation > 10% across the athlete's recent times for the same block name. Display includes the actual CV percentage, e.g. `Long Paddle: erratic pacing (14% CV)`.
- **improving** — linear regression slope < −50 ms over the last 3+ records. (Negative slope = times getting faster = improving.)

Each signal row taps through to a chart view showing the trend, the athlete's personal best, and the last 3 entries.

### Training load

Visible on the athlete Performance tab and on each Team's overview:
- **Weekly load** — total km this week by zone.
- **Seasonal load** — running total since the start of the current season.
- **Recovery is excluded from the total km figure** but shown in the zone breakdown.

### KTC training windows

For athletes who have a Kayak Test Cycle (KTC) entry, the development tab includes a window banner that maps the current date to one of the six annual cycle windows: *General Prep 1, General Prep 2, On-Water Return, Specific Prep, Pre-Competition, Post-Competition*. The windows define what kind of testing and training emphasis applies right now.

---

## Season Operations

### Archive a season

When a season is complete, **Settings → Season Management → Archive This Season**. This:

- Marks all completed practices as `isArchived = true` (hidden from Dashboard and Schedule but still accessible from athlete profiles)
- Creates a season archive summary (total practices, total km, etc.)
- **Does not delete any athlete data** — performance records, assessments, regatta results all stay intact

Archived seasons appear listed below with their totals so you can compare year-over-year.

### Calendar view

**Schedule tab** — a month calendar with:
- Blue dots for practice days
- Orange dots for regatta days
- Month navigation arrows
- A **Today** button to jump back to the current week

Tap any day to see what's on that day. Empty days are interactive — tap and you can quickly add a practice.

### Age category reference

**Settings → Age Category Reference.** A read-only table for the current season year showing which birth years fall into U10, U12, U14, U16, U18, Senior. Age is computed as `current calendar year − birth year` — no cutoff date.

### Data reset

**Settings → Data Management** has two destructive buttons:

- **Reset Session Data** — clears all practices, blocks, attendance, performance times. Keeps athletes, teams, assessments, fitness tests, regatta results, height records.
- **Reset All Data** — clears everything.

Both require confirmation. Both are intended for development/testing or starting completely fresh. **There is no undo.**

---

## Tips, Gotchas, and FAQs

### Why can't I delete a completed practice?

By design — completed practices preserve attendance and performance history. To clear them, archive the season instead (Settings → Season Management).

### Why can't I delete this athlete?

They have practice history. CoachSync protects historical records. Mark them **Inactive** instead (Edit Athlete → toggle Active off). They'll disappear from team rosters and attendance lists but their data is preserved.

### How are age categories calculated?

`Current calendar year − birth year`. No month or day cutoff. So an athlete born in December 2014 is the same category in 2026 as an athlete born in January 2014.

Categories:
- Under 5 → "N/A"
- 5–10 → "U10"
- 11–12 → "U12"
- 13–14 → "U14"
- 15–16 → "U16"
- 17–18 → "U18"
- 19+ → "Senior"

### Time entry formats accepted

The parser accepts up to three fractional digits, normalised to milliseconds:

- **`M:SS.xx`** — minutes : seconds . centiseconds. Examples: `1:23.4`, `1:23.45`, `1:23.456`.
- **`H:MM:SS.xx`** — hours : minutes : seconds . centi/milli. For long pieces: `1:02:03.45`.
- **`H:MM:SS:MMM`** — four-part colon-separated, for milliseconds: `1:02:03:456`.
- **Seconds only** — integer or decimal: `65`, `83.4`, `83.456`.
- **`DNS`** — Did Not Start.
- **`DNF`** — Did Not Finish.
- Empty — pending (you can come back later).

### Will my data sync between my iPhone and Mac?

**Not in V1.0.** Each device stores its own data independently. Cross-device sync via iCloud is the planned V1.1 feature.

In the meantime: pick one device as your primary (most coaches use iPhone for poolside/dockside logging) and treat the Mac as a separate environment.

### Where does my data live?

In SwiftData's local sandboxed container on the device. It's included in your standard iOS or macOS device backups (iCloud Backup, Finder/iTunes backup, Time Machine) but is never transmitted by CoachSync itself.

### What happens to my data if I uninstall?

Uninstalling deletes the app and all its data. There is no cloud copy to restore from in V1.0. If you want to keep your data, back up your device before uninstalling.

---

## Beta Tester Notes

### What's worth poking at most

If you have limited time, focus on:

1. **Add an athlete** (manually + via CSV)
2. **Create a team and add the athlete to it**
3. **Schedule a practice with at least 2 different block types**, including one tracked (Paddle Distance or Paddle Time Pieces) and one checkpoint (Technique or Weights)
4. **Log the practice end-to-end**: attendance → block entry → summary → complete
5. **Open the athlete's profile** and verify the practice shows up in Session History, the block result shows in Performance Log
6. **Force-quit the app** (swipe up app switcher → swipe up on CoachSync) and **relaunch** — confirm data persists
7. **Add a technical assessment** to see the Development Focus Panel update

### Known limitations in V1.0 (beta)

- **No cross-device sync** — coming in v1.1
- **No undo on Reset Data buttons** — they really do wipe everything
- **No reminder notifications** — CoachSync doesn't ping you for upcoming practices
- **No multi-coach support** — single-user assumption (you own your data on your device)
- **TestFlight build expires 90 days from upload** — you'll be prompted to install an update before expiration

### Reporting bugs

Best path: **inside the app, take a screenshot** (Side button + Volume Up on iPhone; Cmd+Shift+3 on Mac), then **long-press the screenshot preview** (iPhone) or open the screenshot. TestFlight will offer a feedback prompt — your description, the screenshot, and the build context all flow back to the developer.

### Build expiration

Each TestFlight build expires **90 days from upload**. When a new build is available, you'll get a notification through the TestFlight app and an email. Tap **Update** to install the new version. Your data is preserved across updates.

---

*Last updated: May 18, 2026 · CoachSync v1.0 (1) · Built for paddling coaches by paddling coaches*
