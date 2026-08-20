# AthleteIQ — Full Build Guide (A → Z)

This guide takes you from an empty machine to a running AthleteIQ v1
(Flutter app + Firebase backend), using the code already written in
this repo. Copy-paste the terminal blocks in order.

**Scope of v1**, honestly stated: everything in Sections 1–13 and 15–17
of your project doc (data collection, sport-specific check-ins,
rule-based Risk Model, Recommendation Engine, Orchestrator, coach
approval, athlete/coach journeys). Section 14/16's ML classifiers,
Knowledge Agent, and Q&A are Phase 2+ — the doc itself frames those as
post-launch upgrades, not launch requirements.

---

## Phase 0 — Install the tools

Pick the tab for your OS. (You're on Windows PowerShell based on the
terminal you're using — follow the Windows column.)

### Windows (PowerShell)

```powershell
# --- Flutter SDK ---
# (skip this if you already cloned it — you're at C:\Users\<you>\flutter)
git clone https://github.com/flutter/flutter.git -b stable $HOME\flutter

# Add Flutter to PATH permanently (current user). Close and reopen
# PowerShell after this for it to take effect.
[Environment]::SetEnvironmentVariable(
  "Path",
  "$([Environment]::GetEnvironmentVariable('Path','User'));$HOME\flutter\bin",
  "User"
)
```

Close this PowerShell window, open a **new** one, then:

```powershell
flutter doctor
```

`flutter doctor` tells you what's missing (Android Studio, Visual
Studio for Windows desktop, Chrome). Install whatever it flags — you
need at least one target (Android emulator or Chrome) to run the app.

```powershell
# --- Node.js (for Firebase CLI + Cloud Functions) ---
winget install OpenJS.NodeJS.LTS
```

Close and reopen PowerShell again, then verify:

```powershell
node -v   # should print v20.x or similar
```

```powershell
# --- Firebase CLI ---
npm install -g firebase-tools
firebase login
```

```powershell
# --- FlutterFire CLI (generates firebase_options.dart) ---
dart pub global activate flutterfire_cli

# Add the pub global bin folder to PATH permanently
[Environment]::SetEnvironmentVariable(
  "Path",
  "$([Environment]::GetEnvironmentVariable('Path','User'));$HOME\AppData\Local\Pub\Cache\bin",
  "User"
)
```

Close and reopen PowerShell once more before continuing to Phase 1 —
every "add to PATH" step above only applies to new terminal windows.

### macOS / Linux (bash/zsh)

```bash
# --- Flutter SDK ---
git clone https://github.com/flutter/flutter.git -b stable ~/flutter
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
source ~/.bashrc
flutter doctor
```

```bash
# --- Node.js ---
# macOS:
brew install node
# Ubuntu/Debian:
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

node -v
```

```bash
# --- Firebase CLI ---
npm install -g firebase-tools
firebase login
```

```bash
# --- FlutterFire CLI ---
dart pub global activate flutterfire_cli
```

---

## Phase 1 — Create the Firebase project

```bash
firebase projects:create athleteiq-app --display-name "AthleteIQ"
```

If that project ID is taken, pick another (must be globally unique) —
substitute it everywhere below.

In the [Firebase Console](https://console.firebase.google.com):
1. Open your new project → **Build → Authentication → Get started** →
   enable **Email/Password**.
2. **Build → Firestore Database → Create database** → start in
   **production mode** → pick a region close to you.
3. **Build → Functions** — no action needed yet, just note it requires
   the **Blaze (pay-as-you-go)** plan. The free tier covers this app's
   usage during development; you won't be charged unless you scale
   past it.

---

## Phase 2 — Get this repo onto your machine and into git

You already have the full project structure (this exact repo) — unzip
it, then:

```bash
cd athleteiq
git init
git add .
git commit -m "Initial AthleteIQ scaffold"
```

Create an empty repo on GitHub (no README/license, so there's no merge
conflict), then:

```bash
git remote add origin https://github.com/<your-username>/athleteiq.git
git branch -M main
git push -u origin main
```

---

## Phase 3 — Turn the folder into a real Flutter project

The `lib/` folder you have is source code, not a full Flutter project
yet (no Android/iOS/web scaffolding). Generate that scaffolding
in-place without overwriting your code:

```bash
cd athleteiq
flutter create --platforms=android,ios,web --org com.yourcompany --project-name athleteiq .
```

Flutter will merge in `android/`, `ios/`, `web/`, etc. and leave your
`lib/`, `pubspec.yaml` alone (it detects `pubspec.yaml` already exists
and won't clobber it — but if it prompts to overwrite `pubspec.yaml`,
say **no**).

```bash
flutter pub get
```

---

## Phase 4 — Connect Flutter to Firebase

```bash
flutterfire configure --project=athleteiq-app
```

Select the platforms you plan to run (at minimum: android, ios, web).
This generates `lib/firebase_options.dart` — **do not hand-write this
file**, the CLI fills it with your real project's client IDs, which
`main.dart` already imports.

---

## Phase 5 — Deploy Firestore rules and indexes

```bash
firebase use athleteiq-app
firebase deploy --only firestore:rules,firestore:indexes
```

This pushes `firestore.rules` (the coach/athlete permission boundaries)
live. Nothing works securely without this step.

---

## Phase 6 — Install and deploy the Cloud Functions

```bash
cd functions
npm install
npm run build
cd ..
firebase deploy --only functions
```

This deploys `recalculateRisk` — the callable function that turns a
check-in into Training Load → ACWR → Risk Level → Recommendation — plus
`nightlyRecalculateRisk`, `askAthleteIQ`, and the Phase 11 / G3 view
triggers (`onRiskLatestWritten`, `onCheckInWritten`,
`onAthletePrivacyUpdated`). You can watch them run later
with:

```bash
firebase functions:log
```

---

## Phase E2 — Ask AthleteIQ (LangChain)

The Ask AthleteIQ tab calls the `askAthleteIQ` Cloud Function
(`functions/src/aiChat.ts`). That function loads the athlete's last 14
days of check-ins and `riskResults/latest`, then answers through a
LangChain `ChatAnthropic` chain. The model is instructed not to invent
numbers. Conversation history is stored at
`athletes/{uid}/aiChat/{messageId}` (already covered by `firestore.rules`).

### Environment variables (`functions/.env`)

Copy `functions/.env.example` to `functions/.env` (gitignored) and fill in:

| Variable | File | Purpose |
|----------|------|---------|
| `ANTHROPIC_MODEL` | `functions/.env` | Model id (safe to deploy). Defaults to `claude-sonnet-5`. |
| `ANTHROPIC_API_KEY` | `functions/.secret.local` | **Local emulator only.** Gitignored. |

**Do not put `ANTHROPIC_API_KEY` in `functions/.env`.** Firebase deploy loads
`.env` as plain environment variables; binding the same name as a Secret
Manager secret fails with “Secret environment variable overlaps non secret
environment variable”.

Restart the Functions emulator after changing `.secret.local`. Do not commit
either file. For production, store the key in Secret Manager and bind it
onto the LLM functions (`defineSecret` in `functions/src/index.ts`):

```bash
firebase functions:secrets:set ANTHROPIC_API_KEY
firebase deploy --only functions
```

Creating the secret is not enough — each callable that calls Claude
must list `secrets: [anthropicApiKey]` so Cloud Run mounts it as
`process.env.ANTHROPIC_API_KEY`. Confirm with:

```bash
firebase functions:describe askAthleteIQ --project athleteiq-app
```

The `secretEnvironmentVariables` list must include `ANTHROPIC_API_KEY`.
Do not put the same key in a deployed `.env` file (Firebase rejects
a secret and an env var with the same name). Local emulator still
reads `functions/.env`.

### Local emulator

```bash
cd functions
npm install
npm run build
cd ..
firebase emulators:start --only auth,functions,firestore
```

Then run the app against the emulator:

```bash
flutter run --dart-define=USE_EMULATOR=true
```

Ask a few questions from the Ask AthleteIQ tab (e.g. "Why am I fatigued
this week?", "Should I train tomorrow?", "How has my sleep been?"). If
`ANTHROPIC_API_KEY` is set, replies come from Claude and are grounded in
that athlete's Firestore data. If the callable fails, Flutter falls back
to labeled local rule-based answers (prefixed in chat) so the screen still
responds — not fabricated demo history.

---

## Phase E3 — Knowledge Agent (supporting research)

There is **no separate Supporting Research screen** (Phase F audit).
Grounded citations are shown on the coach athlete dashboard under
**Why this call** (`lib/screens/coach_dashboard_screen.dart`).

The Knowledge Agent (`functions/src/knowledgeAgent.ts`) chunks the
local notes in `functions/knowledge/` (session-RPE, ACWR + Section 18.2
controversy, Banister Fitness–Fatigue), embeds them into LangChain's
in-memory vector store, and retrieves by the assessment's factors.
`runRiskPipeline` writes `researchNote` + `researchCitations` onto
`riskResults/latest`. With `ANTHROPIC_API_KEY` the note is an LLM
paraphrase of retrieved chunks only; without it, retrieved text is
shown as-is. No live web search.

---

## Phase E4 — Orchestrator agent (tool calling)

The live recommendation is no longer the inline if/else in
`buildRecommendation()`. That function is **kept and flagged**
(`@deprecated`) so every run can store the old decision next to the
new one.

`runOrchestratorAgent()` in `functions/src/orchestratorAgent.ts` is a
LangChain tool-calling loop: `ChatAnthropic.bindTools(...)` then
invoke until the model stops calling tools (same Anthropic setup as
Phase E2). It must call tools — it is not handed a precomputed
risk/performance pair.

### Tools (`functions/src/orchestratorTools.ts`)

| Tool | Wraps | Returns |
|------|--------|---------|
| `getRiskAssessment(athleteId)` | `assessRisk()` in `riskModel.ts` | risk level, ACWR, loads, recovery, reason — **not** performance |
| `getPerformancePrediction(athleteId)` | `assessRisk()` + `calculateFitnessFatigue()` | GOOD / AVERAGE / DECLINING plus Banister index |
| `getAthleteHistory(athleteId, days)` | `loadCheckIns()` | last N check-ins (load, sleep, HRV, fatigue) |

### Hard constraint

The system prompt states: **protecting the athlete comes first**. If
risk is MEDIUM/HIGH or the signals are ambiguous, safety wins over
performance. Never the reverse. After the model returns, a safety
check still rejects a "train as planned" action when risk is elevated
and falls back to the rule-based action (`safetyOverride: true`).

### Where the comparison lives

On `athletes/{uid}/riskResults/latest`:

- `recommendation` / `reason` — agent's (or fallback) decision
- `ruleBasedRecommendation` / `ruleBasedOrchestratorNote` — old if/else
- `orchestratorAgreedWithRules` — whether they match
- `orchestratorSource` — `agent` or `rules_fallback`

Full tool trace (name, input, output, order, why) is written to
`athletes/{uid}/orchestratorTraces/{id}` (Admin SDK write; coach and
athlete may read).

Without `ANTHROPIC_API_KEY` the pipeline uses `buildRecommendation()`
and still stores the comparison fields (they will agree).

### Compare on known athletes

```bash
cd functions
npm run test:orchestrator
```

This runs four fixture athletes in
`functions/src/orchestratorFixtures.ts` (Maya spike / Arthur climb /
Jordan steady / Sam ambiguous) through the tools and the old rules,
then through the agent if a key is set. Check that HIGH/MEDIUM never
get a full-training plan, and that Arthur (MEDIUM + strong
performance) still reduces intensity.

---

## Phase E5 — Graded recommendation options (Section 16.3)

The primary `recommendation` field is unchanged (Orchestrator output).
Each risk recalculation also writes **`gradedOptions`**: three
Conservative / Moderate / Minimal change choices, each with a one-line
`reason`.

Generated by `generateGradedOptions()` in
`functions/src/gradedRecommendations.ts` using the same LangChain +
Anthropic setup as Phase E2 (`ANTHROPIC_API_KEY` / `ANTHROPIC_MODEL`).
Without a key, rule-based fallbacks are built from the sport templates in
`recommendationEngine.ts`.

Stored on `athletes/{uid}/riskResults/latest`:

| Field | Purpose |
|-------|---------|
| `recommendation` | Primary orchestrator decision (unchanged) |
| `gradedOptions` | `[{ tier, action, reason }, …]` — 2–3 options |
| `gradedOptionsSource` | `llm` or `rules` |

**Coach UI:** `lib/screens/coach_dashboard_screen.dart`
(`CoachDashboardScreen` — the Phase F athlete-detail / approval view).
When `recommendationStatus == 'pending'`, graded options render in a
row beneath the primary recommendation. Each card has **Approve this**,
which sets `recommendation` to that option's `action` and marks it
`approved`. **Approve primary** still approves the orchestrator text
as-is.

---

## Phase E6 — Hybrid explainability (Sections 13.4 / 14.5)

`assessRisk()` in `functions/src/riskModel.ts` still owns LOW / MEDIUM /
HIGH and GOOD / AVERAGE / DECLINING. Those thresholds are unchanged.

After classification, `enrichAssessmentExplanation()` in
`functions/src/explainabilityLlm.ts` sends the **locked** assessment plus
the last 5 check-ins to the same LangChain + Anthropic stack as Phase E2.
The model writes prose only. It is instructed not to change the labels.

Stored additively on `athletes/{uid}/riskResults/latest`:

| Field | Purpose |
|-------|---------|
| `riskLevel` | Unchanged — still `assessRisk()` output |
| `reason` | Original rule-based sentence + orchestrator note |
| `riskLevelReasoningLLM` | Richer multi-day explanation (falls back to `reason`) |
| `riskLevelPatternFlag` | Optional "Worth a closer look:" note, or null |
| `performanceReasoningLLM` | Interpretive note on the locked performance label |
| `explanationSource` | `llm` or `rules` |

If `ANTHROPIC_API_KEY` is missing or the call fails, the pipeline writes
the existing `reason` into `riskLevelReasoningLLM` and continues. An LLM
outage never blocks a risk write.

Coach dashboard (`CoachDashboardScreen`) shows the LLM paragraph in
**Why this call** when present, plus the pattern flag and performance
read.

---

## Phase E7 — Custom sport classification (Section 12.2)

When an athlete picks **Other (not listed)** on `sport_selection_screen.dart`,
they type a free-text sport. Flutter calls the `classifyCustomSport`
callable (`functions/src/sportClassifier.ts`), which uses LangChain +
Anthropic (Phase E2) to map the name to the nearest group:

Endurance, Team/Contact, Strength/Power, Skill/Precision, or Combat.

The classifier **returns** the mapping; the selection screen **adds** it to
the multi-select list (`persist: false`). Saving calls `setSports()` with
the full list. If `persist` is omitted (older clients), the callable
**appends** the custom sport instead of replacing the list.

Stored on `athletes/{uid}`:

| Field | Purpose |
|-------|---------|
| `sports` | Ordered array of sport names (first is primary) |
| `sportGroups` | Parallel array of group ids |
| `sport` | Primary name — kept in sync for older readers |
| `sportGroup` | Primary group id, or `other` when confidence is low |
| `sportClassificationConfidence` | `high` or `low` (last custom add) |
| `sportClassificationSource` | `llm` or `rules` |

If confidence is **low** (or the LLM/API fails), that custom entry uses
`other` so recommendation templates use the neutral generic wording in
`recommendationEngine.ts`. The athlete is never blocked.

Listed sports from the picker are classified locally (no LLM).

---

## Multi-sport athletes

`sport_selection_screen.dart` is multi-select. An athlete can pick Rugby
**and** Weightlifting, or add a custom sport on top of listed ones.

**Which sport drives today's wording?** Option (a): the check-in form asks
**Which sport was today's session?** when more than one sport is stored.
That session's group drives Section 12.3 performance framing, Section 15.3
RPE / recommendation templates, and the risk pipeline / weekly report /
Ask AthleteIQ context. Single-sport athletes do not see the extra picker
(their only sport is used). Rest days still store the primary sport.

Profile, roster, and performance tips show **all** sports
(`sportsLabel`). `AthleteProfile.fromMap` still accepts a legacy single
`sport` string.

---

## Phase E8 — Pain report urgency triage

Phase F/G audit: `lib/screens/report_pain_screen.dart` already existed
(body area + severity, seeded dummy rows, no notes). Coach alerts and
per-athlete pain history on the dashboard were **missing entirely**.

The form now starts empty (Phase G2: no Left knee / Right ankle seed),
collects free-text notes, and submits through
the `submitPainReport` callable (`functions/src/painUrgency.ts`).
LangChain + Anthropic classifies urgency **LOW / MEDIUM / HIGH**, biased
conservatively: uncertainty is at least MEDIUM. Missing API key or LLM
failure uses the same conservative rule fallback.

Stored on `athletes/{uid}/painReports/{id}`:

| Field | Purpose |
|-------|---------|
| `areas` | Body location + severity 1–5 |
| `note` | Original free-text |
| `urgency` | `LOW` / `MEDIUM` / `HIGH` |
| `urgencyReason` | Short coach-facing sentence |
| `urgencySource` | `llm` or `rules` |

HIGH reports also write `coaches/{coachUid}/alerts/` and set
`latestPainUrgency` on the athlete profile. Roster shows a coral banner
and a **PAIN** chip.

**Coach UI:** `CoachDashboardScreen` (`lib/screens/coach_dashboard_screen.dart`)
streams `athletes/{uid}/painReports/` (newest first) in a read-only
**Pain reports** section — full history, honest empty state, and a HIGH
triage banner when the latest flagged report needs review. Firestore rules
block coach writes to this collection; the UI has no edit actions.
UI copy states this is a **triage aid, not a diagnosis**.

---

## Phase E9 — Weekly report narrative

Phase F audit: **Weekly report** was **missing entirely** (wireframe
"Week in review" had no screen).

`lib/screens/weekly_report_screen.dart` shows structured rows (sessions,
sleep, peak ACWR, coach adjustments) and a **daily load bar chart** as
primary content. Reach it from **Week in review** on
`CoachDashboardScreen`.

The `getWeeklyReport` callable (`functions/src/weeklyReport.ts`) pulls
check-ins for the selected Mon–Sun week, computes stats server-side,
then optionally adds a 2–3 sentence LangChain narrative grounded **only**
in those numbers. Cached at `athletes/{uid}/weeklyReports/{weekStart}`.

If `ANTHROPIC_API_KEY` is missing or the LLM fails, a rule-based summary
from the same numbers is shown instead.

---

## Phase E10 — Sport-group performance framing (Section 12.3)

The Banister Fitness–Fatigue band in `assessRisk()` is still
**GOOD / AVERAGE / DECLINING** for every sport — one model, not one per
group. `PERFORMANCE_FRAMES` in `functions/src/riskModel.ts` looks up the
athlete's `sportGroup` and phrases that locked band:

| Group | Framing |
|-------|---------|
| Endurance | Time / pace |
| Team/Contact | Coach-rated readiness |
| Strength/Power | Max output |
| Skill/Precision | Match result + readiness |
| Combat | Coach-rated readiness + sparring |
| Other | Generic GOOD / AVERAGE / DECLINING |

Stored next to the canonical band on `riskResults/latest`:
`performanceFrame`, `performanceFrameAxis`. Coach and athlete StatCards
use the axis as the label and the framed phrase as the value. Orchestrator
rules still key off the canonical band.

---

## Phase E11 — Team settings / default action % (Section 18.4)

Each coach has `coaches/{coachUid}/teamSettings/default` with
`defaultActionPercent` (10–30, default **20**), optional `teamName`, and
notification preference booleans. The coach **Profile** tab opens
`coach_settings_screen.dart`.

`recommendationEngine.ts` builds HIGH-risk wording from this value
(e.g. "Reduce training volume by 25%…"). `loadTeamSettings()` in
`teamSettings.ts` is read in the risk pipeline before the orchestrator
and graded options run.

**Not adjustable here:** ACWR thresholds (1.5 / 1.3 / 0.8–1.3) in
`riskModel.ts` / `calculations.ts` — fixed research-backed constants;
code comments note the Section 18.4 distinction.

---

## Phase E12 — FCM alerts (nightly)

`athletes/{uid}/alerts/{id}` remains **server-write only** (Priority Fix #2
in `firestore.rules`: athlete + coach read; `allow write: if false`).
Coach copies live at `coaches/{coachUid}/alerts/`.

On sign-in, Flutter requests notification permission and stores
`fcmToken` on `users/{uid}` (`lib/services/fcm_service.dart`).

`nightlyRecalculateRisk` still runs the risk pipeline, then
`evaluateNightlyAlerts()` (`functions/src/nightlyAlerts.ts`) for:

| Trigger | Meaning |
|---------|---------|
| Risk spike | `riskLevel` rank rose vs yesterday's `riskResults/latest` |
| Missed check-in | No check-in for 2+ days |
| Sync failure | Connected device `lastSyncError` or `lastSync` older than 2 days |

Each event writes an alert doc and sends FCM to the athlete and their
coach when a token exists. Athlete **Alerts** (`my_alerts_screen.dart`)
and coach **Alerts** (roster bell → `coach_alerts_screen.dart`) read
those collections with no fake seed rows.

---

## Phase F2 — Forecast & injury-risk charts

Coach dashboard StatCards still show the current ACWR / performance
numbers. Dedicated chart screens (F1 links) now live at:

| Screen | File | Chart |
|--------|------|-------|
| Forecast | `lib/screens/performance_forecast_screen.dart` | Banister band (DECLINING / AVERAGE / GOOD) over time |
| Risk detail | `lib/screens/injury_risk_screen.dart` | ACWR line with 0.8–1.3 sweet-spot and >1.5 danger bands; fatigue 1–5 as a secondary series |

**History.** `runRiskPipeline()` writes `athletes/{uid}/riskResults/latest`
as before, plus a dated snapshot `riskResults/{yyyy-MM-dd}` (`kind:
snapshot`) with ACWR, performance band, recovery, and 7-day fatigue.
Flutter reads that collection via `streamRiskHistory()`. If snapshots
are still sparse (athletes scored before this write), the screens
reconstruct the same ACWR / Banister / recovery rules from check-ins
(`lib/utils/risk_signals.dart`) so the line is not empty.

ACWR cutoffs on the chart are the fixed Section 18.4 constants (not
coach-tunable). The 1.5 danger line is labeled with the Section 18.2
caveat: a conversation flag, not a diagnosis.

---

## Phase F3 — Coach trends, weekly reports hub, supporting research

Three coach-only screens, reachable from the shell and athlete drill-down:

| Screen | File | Purpose |
|--------|------|---------|
| Trends | `lib/screens/coach_trends_screen.dart` | **Team** tab — roster ACWR snapshot bars + team-average ACWR line; **Athlete** tab — multi-week ACWR chart + 35-day session-RPE load bars |
| Weekly reports | `lib/screens/coach_weekly_reports_screen.dart` | One summary card per athlete (current week via `getWeeklyReport`); share, print/copy preview, full `WeeklyReportScreen` |
| Supporting research | `lib/screens/coach_supporting_research_screen.dart` | Reads `researchNote` + `researchCitations` from `riskResults/latest` when the Knowledge Agent (Phase E3) has written them; otherwise static Section 18.1 citations in `lib/data/section_18_1_research.dart` (session-RPE, ACWR + Gabbett 2016, Banister) with a TODO to drop the fallback once pipeline output is universal |

**Navigation**

- `CoachMainLayout` — new **Trends** bottom tab.
- `CoachRosterScreen` app bar — calendar icon → weekly reports hub.
- `CoachDashboardScreen` — **Trends** (pre-selects athlete), **Supporting research**, existing week-in-review.
- `WeeklyReportScreen` — share + copy-for-print actions on the detail view.

**Share** uses `share_plus`; printable text is formatted by `lib/utils/weekly_report_text.dart`.

---

## Phase G — Coach shell (alerts, Ask AI, profile & settings)

Coaches land on `CoachMainLayout` (`lib/screens/coach_main_layout.dart`) with
bottom tabs: **Roster**, **Inbox**, **Trends**, **Alerts**, **Ask AI**, **Profile**.

| Screen | File | Data / behaviour |
|--------|------|------------------|
| Inbox | `lib/screens/coach_inbox_screen.dart` | One row per roster athlete. Preview from latest `athletes/{uid}/messages/`. Unread = last message is from the athlete and newer than `coaches/{coachUid}/inboxRead/{athleteUid}`. Tap opens `coach_message_thread_screen.dart` to read/reply into the **same** messages collection. Genuine empty state if the roster is empty — no seeded threads. Tab badge uses the same unread rule. |
| Alerts | `lib/screens/coach_alerts_screen.dart` | Streams `coaches/{coachUid}/alerts/` (server-written by `nightlyAlerts.ts`). Mirrors `my_alerts_screen.dart` row layout (icon + title + time). **Genuine empty state** when the collection is empty — no seeded rows. Tap → athlete dashboard. |
| Ask AthleteIQ | `lib/screens/coach_ask_athlete_iq_screen.dart` | Roster athlete picker + embedded `AskAthleteIQScreen`. Calls `askAthleteIQ` when deployed; on failure, labeled rule-based fallback in `FirestoreService._generateAiAnswer()` — not fake sample chat history. |
| Profile & settings | `lib/screens/coach_settings_screen.dart` | Coach-only (not `ProfileScreen`). **Team name** + **notification prefs** (`notificationsEnabled`, `notifyRiskSpikes`, `notifyMissedCheckIns`, `notifyHighPain`) persisted to `coaches/{uid}/teamSettings/default`. Also invite code, default action % slider (Section 18.4), logout. |

**Ask AthleteIQ empty state** (`lib/screens/ask_athlete_iq_screen.dart`): when
`aiChat` is empty, shows an honest prompt instead of fabricated conversation
bubbles. Fallback replies are prefixed `[Rule-based fallback — askAthleteIQ
unavailable…]`.

**Firestore rules:** `teamSettings/default` updates validate optional
`teamName` (string) and notification booleans alongside `defaultActionPercent`.
`coaches/{uid}/inboxRead/{athleteUid}` is coach-self read/write (last-read cursor).

---

## Phase G2 — Remove fake/seeded athlete UI data

Wireframe copy (Arthur S., Coach Jenna, Left knee / Right ankle) was leaking
into live screens and looking like real user data. That is a trust issue, not
a missing feature. Athlete-facing screens now show **real Firestore rows or a
genuine empty/loading state** — never fabricated people, messages, or injuries.

| Screen | Before (misleading) | After |
|--------|---------------------|--------|
| `my_alerts_screen.dart` | When `alerts/` was empty, UI could still look populated (seeded prototype rows / placeholder copy that read like real events). | `EmptyState`: **No alerts yet**. List is only `streamAlerts()`. |
| `message_coach_screen.dart` | Hardcoded header **Coach Jenna / CJ**; three fake bubbles if `messages/` was empty. | Header from `users/{coachUid}` via the athlete's `coachUid`. Empty thread: **Send your coach a message**. |
| `report_pain_screen.dart` | Form started with **Left knee** / **Right ankle** demo rows. | `_areas` starts `[]`; `EmptyState` until the athlete adds a location. |
| `profile_screen.dart` | Fallback name **Arthur S.** (and sport **Track & field**) while loading / if the profile was missing. | Spinner while loading; **Complete your profile** if name is empty; sport shows **sport not set** instead of a fake sport. |

`ask_athlete_iq_screen.dart` already dropped its demo chat in Phase G. Do not
reintroduce wireframe names as `??` fallbacks.

**Home — This week.** `athlete_home_screen.dart` no longer hardcodes Mon–Thu
Rest / Light run / Normal session. Rows come from this week's check-ins
(`lib/utils/this_week_plan.dart`): logged rest vs session (easy / moderate /
hard from RPE + duration). Today, if unlogged, shows the **released**
recommendation (`approved` or `modified`). Unlogged past days are **Not logged**;
future days are **No plan yet**. Pending / rejected plans stay behind the
approval gate (`lib/utils/approval_gate.dart`). If there is neither a check-in
this week nor a released recommendation, `EmptyState` — no invented plan.

**Home app bar.** Profile and logout icons were removed. Those live on the
**Profile** tab in `athlete_main_layout.dart`. Alerts and connected-devices
shortcuts remain.

**My performance.** `my_performance_screen.dart` is reachable from home via
the tappable ACWR / recovery / performance stat row (**Performance detail**).
Hardcoded tips (e.g. "Tuesday's load") were replaced with
`lib/utils/performance_tips.dart` — tips from sport, ACWR, recovery trend,
fatigue, sleep on recent check-ins, and optional LLM performance reasoning.
Empty forecast → `EmptyState`; no generic filler tips.

---

## Phase G3 — Enforce athlete privacySettings with the coach

`lib/screens/data_sharing_screen.dart` writes four booleans to
`athletes/{uid}.privacySettings`. Missing keys default to **shared**.

| Key | Coach-facing data |
|-----|-------------------|
| `wearableData` | Sleep, resting HR, HRV on check-ins; recovery trend; device docs |
| `trainingLogs` | Duration, RPE, session-RPE load, ACWR, 7d/28d load, load charts |
| `injuryHistory` | `painReports/`, soreness notes, HIGH-pain roster chip / alerts |
| `dailyFatigueCheckIn` | 1–5 fatigue score, fatigue charts / averages |

Toggles do **not** stop the athlete from logging or HealthKit sync — their own
recommendations still use full data. They hide that category from the coach.

**App layer.** `FirestoreService` redacts when the signed-in user is not the
athlete (`lib/utils/privacy_redaction.dart`). Coach UI shows **Not shared**,
not zeros that look like real logs.

**Rules layer.** Firestore security rules are **document-level**. They cannot
allow a coach to read `sessionDurationMinutes` while hiding `fatigueScore`
on the same `checkins/{id}` document, and they cannot hide
`recommendation` on `riskResults/latest` while still letting the athlete
read the score. App-level redaction is not a security boundary — anyone
with a modified client or a direct Firestore SDK call would see the raw
doc.

Whole collections that match one toggle are still gated in rules:

- `painReports/` — coach read only if `injuryHistory`
- `devices/` — coach read only if `wearableData`
- `weeklyReports/` — athlete read only; coaches get a redacted payload from
  `getWeeklyReport` (Admin SDK)

Mixed documents use a **Cloud Function-filtered view** (same pattern as
weekly reports, persisted so the Flutter app can still stream):

- `checkins/{id}` — athlete read/write only. Contains the full mixed log.
- `checkinsCoachView/{id}` — assigned coach read only; Admin SDK writes.
  `onCheckInWritten` and `onAthletePrivacyUpdated` copy only the keys the
  athlete has shared. A withheld field is **omitted**, not zeroed in the
  client. `FirestoreService.recentCheckIns` / `latestCheckInDate` read this
  collection when the viewer is the coach.
- `riskResults/latest` — coach always; athlete only when
  `recommendationStatus` is `approved` or `modified`.
- `riskResults/athleteView` — athlete-readable filtered copy. Pending:
  scores and status, no recommendation / reason / graded options / LLM or
  orchestrator internals. After approval the released plan is copied in.
  Written by `runRiskPipeline` and `onRiskLatestWritten` (covers the coach
  tapping Approve in the app). Athletes read this doc, not `latest`.

This is why it mattered: the Human Approval Step (spec Sections 6 and 11)
and the data-sharing toggles were UI promises. A coach with the Firebase
console or an athlete with a patched APK could read an unapproved
recommendation or a private fatigue score. The rules now deny those
reads; the Cloud Function is the only writer of the safe copies.

`askAthleteIQ` omits withheld metrics from the model context when the caller
is the coach. Coach alerts of type `pain` / `sync_failure` are filtered in the
app (a list query cannot mix allowed and denied documents).

---

## Phase G4 — Edge-case empty states (No data / Sync failed / Not enough data)

Wireframe **Edge cases & states** now use the Phase B `EmptyState` widget
(`.empty-wrap`) on live screens — not a second ad-hoc column of icons.

### What `coach_dashboard_screen.dart` did before

`FirestoreService.latestRiskResult()` **dropped** the `insufficientData`
document: if the pipeline wrote `{ insufficientData: true, checkInCount: N }`,
the stream returned `null`. The dashboard then showed a generic muted
paragraph — "No forecast for this athlete yet. AthleteIQ needs about 5 days
of check-ins…" — with **no count**, and no `EmptyState`. It did **not**
invent a fake LOW/0.00 score (the null guard prevented that), but it also
threw away `checkInCount`.

### What it does now

`streamRiskLatest()` keeps the flag and count. When there is no calibrated
`RiskResult`, the dashboard (and Forecast / Risk detail) render
`NotEnoughDataScreen`: **"N of 5 check-ins needed to calibrate"** plus days
since the athlete joined.

### The three states

| State | File | When | Copy / actions |
|-------|------|------|----------------|
| No data yet | `lib/screens/no_data_yet_screen.dart` | Athlete home, **zero** check-ins | Log a check-in **and** connect a device |
| Sync failed | `lib/screens/sync_failed_screen.dart` | Connected device matches nightly `hasStaleOrFailedSync` | Heading uses the device **name**. Subtext is the stored `lastSyncError`, or `"{id} has never completed a sync."`, or `"{id} last synced more than 2 days ago."` — same strings as `nightlyAlerts.ts`. HealthKit notes already produced by `readToday()` (`Could not read HealthKit: …`, physical-iPhone-only) are recorded onto `lastSyncError` so this screen can show them. "No samples today" is **not** a failure. |
| Not enough data | `lib/screens/not_enough_data_screen.dart` | Coach dashboard / forecast / risk detail when `insufficientData` or no `latest` score | Progress from `checkInCount` (or check-in list length if the doc is missing) |

Athlete home still uses `EmptyState` for **Building your first forecast**
when there are some check-ins but not a calibrated score (1–4 days).

The HealthKit connect sheet shows the same `EmptyState` (warn) with the
existing `_error` strings (`HealthKit permission was denied…`,
`Could not connect HealthKit: …`, `Sync failed: …`, physical iPhone).

---

## Phase G5 — Loading and error states on every live screen

Happy-path streams were showing empty calendars, empty rosters, or
"not enough data" when Firestore actually failed (permission-denied /
offline). `lib/widgets/async_body.dart` is the shared gate:

- **Waiting** with no event yet → mint `CircularProgressIndicator`
- **`hasError`** → `EmptyState` (warn) with `friendlyError()` copy — never a
  raw `FirebaseFunctionsException` or blank body

`FirestoreService._callRiskEngine()` catches `FirebaseFunctionsException`
and throws `RiskEngineException` with a short sentence. Check-in / import
screens pop with that SnackBar (the log is already saved). Wearable sync
does **not** write `lastSyncError` for a risk-engine miss.

LLM-backed callables (Phase E2+):

| Feature | On API failure / timeout |
|---------|--------------------------|
| Ask AthleteIQ | Labeled rule-based chat fallback; SnackBar if even that write fails |
| Week in review | `EmptyState` + Retry (callable already has a rules narrative when the function itself is up) |
| Custom sport | Add to the multi-select list with `sportGroup: other` and the existing low-confidence SnackBar; persist on Continue |
| Supporting research | Static Section 18.1 citations when Knowledge Agent fields are missing |
| Pain report | Friendly SnackBar — report is not stored locally if the callable fails |

---

## Phase G6 — Visual consistency and accessibility

Wireframe audit against `docs/wireframe.html.html` and
`lib/theme/app_colors.dart`:

**Drift that was fixed**
- Screen padding `20` / card radius `12–16` → `AppSpacing.screenEdge` (14) and
  `AppRadius.card` (8) / `AppRadius.hero` (10)
- Hand-rolled hero gradients (`Color(0xFF153A30)` linear) → `HeroGradientCard`
  (160° `#153A30` → `#0F2A22`)
- Tab bars used `surface` (`#1C1F1D`); wireframe `.tabbar` is `surfaceAlt`
  (`#121412`) with faint unselected labels
- Calendar rest/trained hexes → `AppColors.calendarRest` / `mintTint`; cell
  radius 4px to match `.cal-day`
- Splash title was `Colors.white` → `textPrimary` + Space Grotesk; mint mark
  like `.splash-mark`
- Inbox **NEW** badge was white-on-coral (~2.8:1) → `mintDark` on coral

**Accessibility**
- `AppSpacing.minTapTarget` = 48 on buttons, icon buttons, chips, pills, and
  pain-severity controls
- `RiskChip` keeps wireframe colors (all ≥ 4.5:1 on their chip backgrounds)
  plus a 1px tinted border so HIGH/MEDIUM/LOW stay readable on `#0B0D0C`;
  `Semantics` label; 11px type
- `MaterialApp.builder` clamps `textScaler` to **1.0–1.6** so system text
  scaling works without blowing up rows; `StatCard` / chip labels ellipsize

See `test/contrast_test.dart`.

---

## Phase 7 — Run the app

```bash
# List available devices/emulators
flutter devices

# Run on whichever you have — e.g. Chrome for the fastest first test:
flutter run -d chrome

# Or Android emulator / iOS simulator:
flutter run
```

First run through the app:
1. Sign up as a **Coach** (one account).
2. Sign up as an **Athlete** (second account, or second device/browser
   profile — use an incognito window if testing both in Chrome).
3. In the Firebase Console → Firestore → `athletes/{athleteUid}`,
   manually set `coachUid` to the coach's UID (found in
   Authentication → Users). This is the "assign athlete to coach" step
   — Phase 2 of the roadmap below turns this into a real invite flow
   instead of a manual console edit.
4. As the athlete, submit 5+ daily check-ins (you can backdate test
   data directly in Firestore, or just click through 5 real days) —
   the Risk Model needs that many data points before it'll score
   anything (see the "not enough data" guard in `functions/src/index.ts`).
5. As the coach, open the athlete's dashboard, see the risk score and
   reasoning, and **Approve** the recommendation.
6. Switch back to the athlete account — the approved recommendation
   now appears on their home screen.

---

## Phase A — Theme & design tokens (UI foundation)

Before building screens, lock the visual language to the wireframe so
nothing drifts. Open `docs/wireframe.html.html` and read the top of the
`<style>` block — every hex, radius, and spacing value used across the
phone mockups lives there.

Those values are mirrored in Flutter under `lib/theme/`:

| Wireframe token | Flutter constant | Hex / value |
|-----------------|------------------|-------------|
| `body` background | `AppColors.background` | `#0B0D0C` |
| `.phone` / `.device-icon` bg | `AppColors.surfaceAlt` | `#121412` |
| `.device-card`, `.rec-box` bg | `AppColors.surface` | `#1C1F1D` |
| borders (`.phone`, `.field`, cards) | `AppColors.border` | `#2A2E2B` |
| `.label`, `.athlete-meta` | `AppColors.textMuted` | `#6E736F` |
| body / secondary copy | `AppColors.textSecondary` | `#B4B8B5` |
| headings | `AppColors.textPrimary` | `#EDEFEC` |
| `.mint`, `.tab.active` | `AppColors.mint` | `#2FE6B8` |
| `.btn-mint` text | `AppColors.mintDark` | `#06231C` |
| `.coral`, `.risk-high` | `AppColors.coral` | `#FF6A4D` |
| `.risk-med`, `.tier-partial` | `AppColors.amber` | `#E6A83B` |
| `.risk-high` chip bg | `AppColors.riskHighBg` | `#2A1810` |
| `.risk-med` chip bg | `AppColors.riskMedBg` | `#241C10` |
| `.risk-low` chip bg | `AppColors.riskLowBg` | `#10201C` |
| card radius (8px) | `AppRadius.card` | `8` |
| `.risk-chip` radius | `AppRadius.chip` | `10` |
| screen padding | `AppSpacing.screenEdge` | `14` |

Fonts: **Inter** for body copy, **Space Grotesk** for headings — both
loaded via `google_fonts` in `lib/theme/app_theme.dart`.

**Rule:** if you change a color in the wireframe, update
`lib/theme/app_colors.dart` first, then re-check the widget catalog
(Phase B below).

---

## Phase B — Shared widget library

Every screen in Phase C onward should compose from these reusable
widgets in `lib/widgets/` — don't re-style cards, chips, or buttons
inline.

### What's included

| Widget | File | Wireframe source |
|--------|------|------------------|
| `RiskChip` | `risk_chip.dart` | `.risk-chip` |
| `AppCard` | `app_card.dart` | `.device-card`, `.rec-box`, `.acwr-box` |
| `PrimaryButton` / `SecondaryButton` | `app_buttons.dart` | `.btn-mint`, `.btn-outline` |
| `StatTile` | `stat_tile.dart` | `.stat` row |
| `SectionHeader` | `section_header.dart` | `.label` |
| `EmptyState` | `empty_state.dart` | `.empty-wrap` |

Bonus widgets already in the repo (used by the catalog, not required
for every screen): `HeroGradientCard`, `SelectableChip`, `PillRow`.

### Visually verify everything

A widget catalog lives at `lib/dev/widget_catalog.dart`. Open it with
either approach:

```bash
# Option 1 — launch straight into the catalog (debug only)
flutter run -d chrome --dart-define=SHOW_WIDGET_CATALOG=true

# Option 2 — run the app normally, then navigate to /dev/widgets
flutter run -d chrome
```

In the catalog, scroll through each section and compare side-by-side
with `docs/wireframe.html.html` in a browser. Pay special attention to:

1. Risk chip colors on HIGH / MEDIUM / LOW
2. Card border (`#2A2E2B`) and 8px corner radius
3. Mint primary button (`#2FE6B8` fill, `#06231C` text)
4. Empty-state warn variant (coral icon on `#2A1810` background)
5. Section header uppercase tracking

When you're satisfied, remove the temporary catalog entry from
`main.dart` (the `SHOW_WIDGET_CATALOG` home override and `/dev/widgets`
route) — or leave them behind `kDebugMode` as they are now.

### Using widgets in a real screen

```dart
import '../widgets/app_card.dart';
import '../widgets/risk_chip.dart';
import '../widgets/stat_tile.dart';
import '../widgets/section_header.dart';

// ...
const SectionHeader('Today'),
AppCard(
  title: 'Injury risk',
  trailing: RiskChip(level: 'MEDIUM'),
  child: Row(
    children: [
      Expanded(child: StatTile(label: 'ACWR', value: '1.4', compact: true)),
      SizedBox(width: AppSpacing.statGap),
      Expanded(child: StatTile(label: 'Load', value: '380', compact: true)),
    ],
  ),
),
```

---

## HealthKit / Apple Watch (real device — you must finish this in Xcode)

AthleteIQ now reads **real** HealthKit samples on a physical iPhone and merges them into `athletes/{uid}/checkins/{YYYY-MM-DD}`. Garmin / Whoop stay **Coming soon** until those vendors approve API access.

The Flutter side is in `lib/services/health_sync_service.dart`. It pulls resting heart rate, HRV (SDNN), sleep, and workout duration, then `FirestoreService.mergeWearableCheckIn()` writes those fields **without overwriting** RPE / fatigue / soreness. If HealthKit has no HRV for the day, the `hrv` field is omitted (never stored as 0).

Sync runs when you tap **Authorize & Connect Apple Watch** or **Sync Now**, and again when the athlete shell opens or the app resumes.

### YOU must do this in Xcode (HealthKit will not work until you do)

HealthKit is an Apple capability. I added `ios/Runner/Info.plist` usage strings and `ios/Runner/Runner.entitlements`, but **you still have to turn the capability on in Xcode** and run on a real iPhone (not the simulator, not Chrome).

1. On a Mac, open the iOS project:
   ```bash
   open ios/Runner.xcworkspace
   ```
   (Use the **workspace**, not `Runner.xcodeproj`, so CocoaPods is included.)
2. Select the **Runner** target → **Signing & Capabilities**.
3. Click **+ Capability** → add **HealthKit**.
4. Leave **Clinical Health Records** unchecked. You only need the default HealthKit capability.
5. Confirm **Signing** uses your Apple Developer team (free personal team is enough for device testing).
6. Plug in the iPhone that is paired with the Apple Watch. Trust the computer. Select that device as the run destination.
7. In Xcode: **Product → Run** (or from the repo: `flutter run` with that iPhone selected).
8. On the phone: open AthleteIQ → Connect Device → **Authorize & Connect Apple Watch**. Allow Heart Rate, Heart Rate Variability, Sleep, and Workouts when iOS asks.
9. Confirm the watch has synced to the Health app first (open **Health → Browse** and check Resting Heart Rate / HRV / Sleep / Workouts). If Health is empty, AthleteIQ will correctly write nothing — not placeholders.
10. In the Firestore emulator UI (or production Firestore if you are not using `--dart-define=USE_EMULATOR=true`), open:
    `athletes/{yourUid}/checkins/{YYYY-MM-DD}`
    You should see real `restingHeartRate`, `sleepHours`, optional `hrv`, and `sessionDurationMinutes` from today's workouts.

If you skip step 3, iOS will reject HealthKit access even though the Dart code is correct.

### What I already added (do not redo)

- `health: ^13.3.1` in `pubspec.yaml`
- `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` in `ios/Runner/Info.plist` — aligned with `health_sync_service.dart` (resting HR, HRV/SDNN, sleep, workouts; read-only merge into check-ins; no write-back to Apple Health)
- `ios/Runner/Runner.entitlements` with `com.apple.developer.healthkit`
- `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements` on Debug / Release / Profile
- `devices/` Firestore rules (athlete write, coach read) — already in `firestore.rules`

---

## Health Connect / Android wearables (real device)

Android uses the **same** `HealthSyncService` + `mergeWearableCheckIn()` path as HealthKit. There is no second writer. Samples land in `athletes/{uid}/checkins/{YYYY-MM-DD}` and `athletes/{uid}/devices/health_connect`.

Most Android wearables (Honor, Redmi, Mibro, Kieslect) are **Tier 2**: heart rate, sleep, and steps. HRV is requested if Health Connect has it (RMSSD, not Apple's SDNN) but is **omitted from the check-in when missing** — never stored as 0. The profile `deviceTier` is set to `tier2`, so coach UI copy is **HRV not available for this athlete**.

### YOU must do this on the test phone

1. Install **Health Connect** from the Play Store if it is not preinstalled:  
   https://play.google.com/store/apps/details?id=com.google.android.apps.healthdata  
   On many Android 14+ phones it is a system component; on others it is a separate app. AthleteIQ shows **Install Health Connect** when the SDK is missing instead of crashing.
2. Open the vendor app for the watch/band (Honor / Xiaomi / etc.) and turn on **sync to Health Connect**. Phone-only step and sleep data also counts for a first test (Health Connect → App permissions → allow those sources).
3. USB-debug the phone, then from this repo:
   ```bash
   flutter run -d <android-device-id>
   ```
   Chrome and the Windows desktop build cannot talk to Health Connect.
4. In AthleteIQ: Connect Device → **Honor / Redmi / other** → **Authorize & Connect Health Connect**. Allow Heart Rate, Sleep, Exercise, and Steps. HRV is optional.
5. Confirm Firestore `athletes/{uid}/checkins/{YYYY-MM-DD}` has real `restingHeartRate` / `sleepHours` / `sessionDurationMinutes` when those samples exist — not zeros. `hrv` should be **absent** on typical Tier 2 watches. `devices/health_connect.metrics.steps` may be present.

### What I already added (do not redo)

- Same Dart API: `requestPermissions()` / `readToday()` / `syncToday()` in `lib/services/health_sync_service.dart`
- `MainActivity` extends `FlutterFragmentActivity` (required for Health Connect permission sheets on Android 14)
- Manifest read permissions: resting HR, heart rate, HRV, sleep, exercise, steps, plus `ACTIVITY_RECOGNITION` for steps, plus the Health Connect rationale intent-filter / `ViewPermissionUsageActivity` alias / `<queries>` for `com.google.android.apps.healthdata`
- `minSdk` at least 26; `android.enableJetifier=true`
- Rationale strings in `android/app/src/main/res/values/strings.xml`

---

## Tier 3 manual resting heart rate (Section 9)

Tier 3 athletes have no wearable. Manual check-in already collected RPE,
duration, sleep, and fatigue. Resting HR was device-only.

`manual_daily_log_screen.dart` and `checkin_screen.dart` now show an
**optional** resting-HR field when `athletes/{uid}.deviceTier` is `tier3`
(or anything other than `tier1` / `tier2`). Copy makes clear it is
approximate ("if you know it, e.g. from checking your pulse"). Default is
**Skip** — the field is omitted from the write so a later wearable merge
is not wiped.

**No manual HRV.** `calculateRecoveryTrend` in `functions/src/calculations.ts`
already falls back to resting HR + sleep + fatigue when HRV is missing
(`usedHRV: false`). That logic was not changed.

### Manual / Play Console (you)

- Copy `health_connect_rationale` into Play Console **Data safety** (Health / fitness, read-only).
- Host a privacy-policy URL and keep the `VIEW_PERMISSION_USAGE` alias pointing at an activity that can open it (currently `MainActivity`). Google may require this for Health Connect review.
- Garmin / Whoop remain **Coming soon** until those vendor APIs are approved — they do not go through Health Connect in this build.

`devices/` and `checkins/` rules are platform-agnostic: `allow write: if isSelf(athleteUid)`. iOS and Android use the same collections; only the device document id differs (`apple_watch` vs `health_connect`).

---

## Phase 8 — Local development loop (fast iteration, no deploy each time)

```bash
# Terminal 1: run the Firebase emulators (Auth + Firestore + Functions)
firebase emulators:start

# Terminal 2: point the Flutter app at the emulators for local testing
```

To use emulators from Flutter, add this near the top of `main()` in
`lib/main.dart` (guard it behind a debug flag so it never ships to
production):

```dart
if (const bool.fromEnvironment('USE_EMULATOR')) {
  FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  FirebaseFunctions.instance.useFunctionsEmulator('localhost', 5001);
}
```

```bash
flutter run -d chrome --dart-define=USE_EMULATOR=true
```

---

## Phase 9 — Ship a real build

### Versioning

Single source of truth: `pubspec.yaml` → `version: MAJOR.MINOR.PATCH+BUILD`

| Platform | Maps to |
|----------|---------|
| iOS | `CFBundleShortVersionString` / `MARKETING_VERSION` = `MAJOR.MINOR.PATCH`; `CFBundleVersion` = `BUILD` |
| Android | `versionName` / `versionCode` from the same Flutter fields |

Bump the `+BUILD` number for every store upload; bump `MAJOR.MINOR.PATCH` when you ship a user-visible release.

### Bundle / application IDs

Shipping identity is `com.athleteiq.app` (Android `applicationId` / iOS `PRODUCT_BUNDLE_IDENTIFIER`). Changing this after a store listing is painful — keep it.

| Platform | File |
|----------|------|
| iOS | Xcode Runner target → **Signing & Capabilities**; `ios/Flutter/ReleasePlaceholders.xcconfig` (`DEVELOPMENT_TEAM` still empty until you pick a team) |
| Android | `android/app/build.gradle.kts` → `applicationId` / `namespace` |
| Firebase | `android/app/google-services.json` `package_name` and `lib/firebase_options.dart` `iosBundleId` |

Register `com.athleteiq.app` as Android and iOS apps in Firebase Console (or re-run `flutterfire configure`) so the client IDs match this package. SHA-1 of the upload keystore is required for Google Sign-In; email/password Auth works without it.

### App icon & splash (generated)

Brand assets live in `assets/branding/` (mint `#2FE6B8` activity mark from the wireframe). Regenerate all platform sizes:

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

**iOS:** `ios/Runner/Assets.xcassets/AppIcon.appiconset/` (20pt–1024pt) + `LaunchScreen.storyboard` splash on `#0B0D0C`.

**Android:** `mipmap-*` launcher icons, adaptive icon, Android 12 splash (`values-v31`), legacy `launch_background.xml`.

Use `assets/branding/app_icon.png` (1024×1024) for App Store Connect and Play Console listing art.

### iOS release (macOS + Xcode required)

1. Set **Team** and **Bundle Identifier** on the Runner target.
2. Confirm **HealthKit** capability is enabled (see HealthKit section below).
3. Archive:
   ```bash
   flutter build ipa --release
   ```
   Or Xcode → **Product → Archive**, then upload to App Store Connect.
4. Optional CI export: edit `ios/ExportOptions.plist` (`YOUR_TEAM_ID`, signing method).

HealthKit usage strings in `ios/Runner/Info.plist` describe what `health_sync_service.dart` actually reads: resting HR, HRV (SDNN), sleep, workout duration — read-only, merged into check-ins without overwriting manual RPE/fatigue/soreness.

### Android release

1. Create an upload keystore (once). From `android/`:
   ```bash
   mkdir -p keystore
   keytool -genkeypair -v -storetype PKCS12 \
     -keystore keystore/upload-keystore.jks \
     -alias upload -keyalg RSA -keysize 2048 -validity 10000
   ```
   Windows (PowerShell): see the exact commands in `android/key.properties.example`.
2. Copy `android/key.properties.example` → `android/key.properties` and fill in paths/passwords.
3. Build:
   ```bash
   flutter build appbundle --release
   ```
   Output: `build/app/outputs/bundle/release/app-release.aab`

Release builds enable R8 minify/shrink when `key.properties` exists. Without it, release falls back to debug signing so local `flutter run --release` still works.

**Health Connect** is live on Android (same `health` package as HealthKit). Play Console **Data safety** still needs the `health_connect_rationale` copy from `res/values/strings.xml`.

```bash
# Android release APK (side-load / testing)
flutter build apk --release

# Web (deployable to Firebase Hosting)
flutter build web --release
firebase deploy --only hosting   # after running `firebase init hosting` once
```

---

## Roadmap — what to build next, in order

This is Sections 14/16/18 of your doc, turned into a build order. Each
phase is additive; nothing here requires reworking Phase 0–9.

### Phase 10 — Wearable sync (Section 4, Tier 1/2)
Apple Watch (HealthKit) and Android Health Connect are in the app.
Garmin and Whoop still require developer approval before you get API
access (Section 10's "Known Challenges" already flags this — apply
early, it can take weeks). Until approved, keep the app fully usable
on Health Connect (Tier 2) or Tier 3 (manual entry).

### Phase 11 — Tighten the athlete/coach data boundary
**Done.** Approach (a) + a rules gate on `latest`, not (b) alone:

Firestore cannot hide one field on a document the athlete is allowed to
read. Gating `latest` on `recommendationStatus == 'approved'|'modified'`
(approach b) is necessary but not sufficient — the athlete still needs
scores / "coach reviewing" while the plan is pending. So the Cloud
Function writes `riskResults/athleteView` with only what is safe to show
a pending-status athlete (or just `insufficientData`). The full
`riskResults/latest` is coach-always and athlete-only after approval.

`FirestoreService.streamRiskLatest` reads `athleteView` for the athlete
and `latest` for the coach. App-level `redactUnreleasedRecommendation`
is no longer the live path (it remains as a unit-tested helper).

The same pattern applies to check-ins: field-level rules are impossible
on a mixed document, so raw `checkins/` is athlete-only and coaches
stream `checkinsCoachView/`.

Athlete-facing surfaces treat **`approved` or `modified`** as released
(coach "Send to athlete" writes `modified`). Pending recs are also
omitted from `askAthleteIQ` context when the caller is the athlete.

### Phase 12 — Explainability Agent v2 / Knowledge Agent (Section 6)
**Done (Phase E3).** Local RAG over `functions/knowledge/` (session-RPE,
ACWR with the Section 18.2 controversy, Banister). Shown on the coach
dashboard under Why this call — there is no standalone Supporting
Research screen. Do not add a live search API; the corpus is pre-vetted.

### Phase 13 — Natural-language Q&A (Section 6)
A callable function that takes the athlete's question + their last 14
days of `DailyEntry` data, and asks an LLM (e.g. the Claude API) to
answer strictly from that data — same shared-signals pipeline you
already built in `calculations.ts`, so the answer stays consistent
with the score the athlete already sees.

### Phase 14 — Trained ML classifier (Section 14.6)
Once you have real outcome data (injury yes/no) logged via the coach
feedback loop (Phase 15 below), export it and train a Logistic
Regression or Random Forest classifier. Swap it in behind the same
`assessRisk()` function signature in `riskModel.ts` so nothing else in
the app has to change.

### Phase 15 — Coach feedback loop (Section 14.4)
Add a "mark this call as wrong" action on the coach dashboard next to
Approve/Reject. Log it to a `feedback` collection — this becomes your
training data for Phase 14, and your coach-trust metric from Section
10's "Known Challenges."

### Phase 16 — Graded recommendation options, competition calendar (Section 16.3–16.4)
**Graded options done (Phase E5).** `gradedOptions` on `riskResults/latest`
+ coach picker on `CoachDashboardScreen`. Still to do: competition
calendar taper via `upcomingCompetitionDate` on the athlete profile.

---

## Troubleshooting

- **`flutterfire configure` fails / can't find project** — run
  `firebase projects:list` to confirm you're logged into the right
  Google account (`firebase login --reauth` if needed).
- **Cloud Function deploy fails asking for billing** — Functions
  require the Blaze plan (Firebase Console → upgrade). It has a
  generous free tier; you won't be charged for dev-level usage.
- **`permission-denied` reading Firestore** — you skipped Phase 5
  (rules aren't deployed yet), or the athlete's `coachUid` isn't set
  to match the signed-in coach's UID. After Phase 11, an athlete
  reading `riskResults/latest` while the plan is still `pending` is
  also denied — that is expected; the app reads `athleteView`. A coach
  reading raw `checkins/` is denied; they stream `checkinsCoachView/`.
- **Coach roster shows no check-ins after deploying these rules** —
  deploy the view triggers (`onCheckInWritten`,
  `onAthletePrivacyUpdated`) and wait for the next check-in, a privacy
  toggle, or `nightlyRecalculateRisk` (it backfills `checkinsCoachView`).
  Until then the coach path is empty on purpose (fail-closed).
- **Risk score never appears** — check `firebase functions:log` for
  errors, and confirm the athlete has 5+ check-in documents (the
  function intentionally refuses to score with less data).
