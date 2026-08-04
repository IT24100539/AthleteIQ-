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
check-in into Training Load → ACWR → Risk Level → Recommendation. You
can watch it run later with:

```bash
firebase functions:log
```

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

```bash
# Android release APK
flutter build apk --release

# iOS (requires macOS + Xcode + an Apple Developer account for real devices)
flutter build ios --release

# Web (deployable to Firebase Hosting)
flutter build web --release
firebase deploy --only hosting   # after running `firebase init hosting` once
```

---

## Roadmap — what to build next, in order

This is Sections 14/16/18 of your doc, turned into a build order. Each
phase is additive; nothing here requires reworking Phase 0–9.

### Phase 10 — Wearable sync (Section 4, Tier 1/2)
Garmin and Whoop both require developer approval before you get API
access (Section 10's "Known Challenges" already flags this — apply
early, it can take weeks). Until approved, keep the app fully usable
on Tier 3 (manual entry), which is what you just built.

### Phase 11 — Tighten the athlete/coach data boundary
Right now `riskResults/latest` is readable by the athlete even while
`recommendationStatus == 'pending'` (the Flutter UI hides it, but the
raw doc isn't blocked at the rules level — see the comment in
`firestore.rules`). Harden this by having the Cloud Function write a
second, sanitized `riskResults/athleteView` doc only at approval time,
and point the athlete's read at that doc instead.

### Phase 12 — Explainability Agent v2 / Knowledge Agent (Section 6)
Add a second Cloud Function that, given a risk result, pulls 1–2
sports-science references relevant to the specific pattern detected
(e.g. ACWR spike → cite Gabbett 2016 with the retraction caveat from
Section 18.2). Store references as static, pre-vetted content first —
don't let this hit a live search API without review, since it's
citing health-adjacent claims to coaches.

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
Extend `recommendationEngine.ts` to return 2–3 options instead of one,
and factor in an `upcomingCompetitionDate` field on the athlete profile
so "reduce training" tapers appropriately near a competition.

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
  to match the signed-in coach's UID.
- **Risk score never appears** — check `firebase functions:log` for
  errors, and confirm the athlete has 5+ check-in documents (the
  function intentionally refuses to score with less data).
