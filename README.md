# AthleteIQ

A coach-approved training load / injury-risk assistant. Flutter app at the
repo root; all server logic is Firebase Cloud Functions in `functions/`.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for how the system fits
together, and [`docs/repo_structure.md`](docs/repo_structure.md) for paths.
The long historical walkthrough is [`AthleteIQ_Build_Guide.md`](AthleteIQ_Build_Guide.md).

> **Not used:** `MODEL_prototype_do_not_use/` is an archived FastAPI experiment.
> The live app never calls it.

---

## Getting Started

This section is for a **fresh clone** with **your own** Firebase project and
API keys — not the original AthleteIQ Firebase project. You need basic
familiarity with Flutter and the Firebase Console.

### 1. Prerequisites

Install and confirm these before cloning:

| Tool | Version this repo expects | Why |
|------|---------------------------|-----|
| **Git** | any recent | Clone the repo |
| **Flutter SDK** | **stable** channel, Dart **≥ 3.3.0 and &lt; 4.0.0** (`pubspec.yaml`) | App at repo root |
| **Node.js** | **20** (`functions/package.json` `"engines"`) | Cloud Functions + Firebase CLI |
| **npm** | comes with Node 20 | `functions/` dependencies |
| **Firebase CLI** | current (`npm install -g firebase-tools`) | Emulators, deploy, secrets |
| **FlutterFire CLI** | `dart pub global activate flutterfire_cli` | Generates `lib/firebase_options.dart` and native config files |
| **Android Studio** (Android / emulator) | with an SDK and a device or AVD | `minSdk` is **26**; Gradle compiles with **Java 17** (`android/app/build.gradle.kts`) |
| **JDK 17** | required by the Android Gradle config | Android builds |
| **Xcode** (iOS only) | latest stable, **macOS only** | iOS simulator / device; HealthKit capability |
| **CocoaPods** (iOS only) | `sudo gem install cocoapods` | iOS native plugins after `flutter pub get` |
| **Chrome** (optional) | any current | `flutter run -d chrome` |

Check the toolchain:

```bash
flutter doctor
node -v    # v20.x
firebase --version
```

Add FlutterFire to your PATH if `flutterfire` is not found (`dart pub global
activate flutterfire_cli`, then the Pub cache `bin` directory).

On **Windows PowerShell**, chain commands with `;` not `&&`.

### 2. Clone the repo and install dependencies

```bash
git clone <your-fork-or-clone-url> athleteiq
cd athleteiq

flutter pub get

cd functions
npm install
cd ..
```

There is no root `package.json`. Dart deps are `pubspec.yaml`; Functions deps
are `functions/package.json`.

### 3. Create your own Firebase project

1. Open [Firebase Console](https://console.firebase.google.com) → **Add project**.
   Pick a unique project ID (the repo’s `.firebaserc` currently says
   `athleteiq-app` — that is **not** yours; you will retarget in step 4).
2. Enable products this app actually uses:
   - **Authentication** → **Email/Password** (the only sign-in method in
     `lib/services/auth_service.dart`).
   - **Cloud Firestore** → create a database (production mode is fine; this
     repo deploys `firestore.rules` next).
   - **Cloud Functions** — deploying `functions/` **requires the Blaze
     (pay-as-you-go) plan**. That is a Google/Firebase requirement: 2nd-gen
     Cloud Functions cannot be deployed on the free Spark plan. Typical student
     / demo traffic stays inside the free usage allotment on Blaze; you are
     billed only if you exceed it.
   - **Cloud Messaging** (optional) — needed for push after a coach approves a
     plan (`FcmService` + `functions/src/recommendationNotify.ts`). The app
     runs without it; in-app alerts still write to Firestore.
3. Log the CLI into the same Google account and select the new project:

```bash
firebase login
firebase use --add
```

That updates `.firebaserc` so later `firebase deploy` hits **your** project.

### 4. Connect Flutter with `flutterfire configure`

From the **repo root** (where `pubspec.yaml` is):

```bash
flutterfire configure
```

Select **your** Firebase project and the platforms you will run (Android,
iOS, web). This **overwrites** the checked-in files that currently point at
the original project:

| Generated / updated file | Role |
|--------------------------|------|
| `lib/firebase_options.dart` | Client Firebase options loaded in `lib/main.dart` |
| `android/app/google-services.json` | Android Google services |
| `ios/Runner/GoogleService-Info.plist` | iOS Google services (created if you enable iOS) |
| `firebase.json` → `flutter.platforms` | Records app IDs for FlutterFire |

Do not keep the placeholder `athleteiq-app` IDs if you are running against
your own backend. Re-run `flutterfire configure` whenever you add a platform.

Android application id in Gradle is `com.athleteiq.app`. Register that package
(and the iOS bundle id from Xcode) in the Firebase Console if FlutterFire
prompts you to create apps.

### 5. Deploy Firestore rules, indexes, and Cloud Functions

Build Functions TypeScript first (also runs as a Firebase `predeploy` hook):

```bash
cd functions
npm run build
cd ..

firebase deploy --only firestore:rules,firestore:indexes,functions
```

- Rules: `firestore.rules`
- Indexes: `firestore.indexes.json`
- Functions source: `functions/` (`firebase.json` `"source": "functions"`)

If deploy fails because Functions are not on Blaze, upgrade the project in
the Console and retry. After a successful functions deploy, callables such as
`recalculateRisk` and `askAthleteIQ` exist on **your** project.

### 6. Anthropic API key (`ANTHROPIC_API_KEY`)

LLM features (Ask AthleteIQ, Orchestrator, research notes, pain triage,
weekly narrative, sport classify, eval judges) read **`process.env.ANTHROPIC_API_KEY`**.
The production binding is `defineSecret('ANTHROPIC_API_KEY')` in
`functions/src/index.ts`. If the key is missing, those paths **fall back** to
rule-based output; risk **bands** (LOW / MEDIUM / HIGH) are never chosen by
the LLM.

1. Create a key at [console.anthropic.com](https://console.anthropic.com).
2. **Production (deployed Functions)** — store it in Google Secret Manager and
   redeploy so Cloud Run mounts it:

```bash
firebase functions:secrets:set ANTHROPIC_API_KEY
firebase deploy --only functions
```

   Creating the secret is not enough. Each LLM callable already lists
   `secrets: [anthropicApiKey]` (`recalculateRisk`, `nightlyRecalculateRisk`,
   `askAthleteIQ`, `classifyCustomSport`, `submitPainReport`, `getWeeklyReport`,
   `evaluateLlmOutput`, `evaluateAthleteLlmHistory`).

3. **Local Functions emulator** — put the key in **`functions/.secret.local`**
   (gitignored), **not** in `functions/.env`:

```
ANTHROPIC_API_KEY=sk-ant-...
```

   Firebase deploy loads `functions/.env` as plain env vars. Binding the
   **same name** as a Secret Manager secret fails with “Secret environment
   variable overlaps non secret environment variable”. That is why
   `functions/.env.example` tells you to keep the key in `.secret.local` for
   the emulator.

Copy the non-secret example:

```bash
cp functions/.env.example functions/.env
```

Restart the emulator after changing `.secret.local`. Never commit
`functions/.env`, `functions/.env.local`, or `functions/.secret.local`.

### 7. Environment variables and dart-defines this repo actually uses

From `functions/.env.example` and the TypeScript/Dart that read `process.env`
/ `--dart-define`:

#### Required for LLM (optional for a rules-only risk demo)

| Name | Where | Required? |
|------|--------|-----------|
| `ANTHROPIC_API_KEY` | Production: Secret Manager via `firebase functions:secrets:set`. Emulator: `functions/.secret.local` | For Claude. Without it, LLMs fall back; `assessRisk()` still runs. |
| `ANTHROPIC_MODEL` | `functions/.env` | No. Default in `functions/src/anthropic.ts` is **`claude-sonnet-5`**. |

#### Optional LangSmith (Orchestrator + Knowledge Agent traces only)

Used in `functions/src/langsmithDevTrace.ts`. **Off** unless you set these.
Do **not** set `LANGCHAIN_TRACING_V2` — auto-tracing would upload raw prompts
(athlete health data).

| Name | Where | Required? |
|------|--------|-----------|
| `LANGSMITH_TRACING` | env / emulator | Must be exactly `true` to send traces |
| `LANGSMITH_API_KEY` | env | Required if tracing is on |
| `LANGSMITH_ENDPOINT` | env | No (LangSmith default API URL) |
| `LANGSMITH_PROJECT` | env | No (defaults to `athleteiq-dev`) |

There is **no** other `functions/.env.example` key. The Flutter app has **no**
Anthropic key; it talks to Firebase only.

#### Flutter dart-defines (debug / local only)

| Define | Used in | Required? |
|--------|---------|-----------|
| `USE_EMULATOR` | `lib/main.dart` | No. `flutter run --dart-define=USE_EMULATOR=true` points Auth **9099**, Firestore **8080**, Functions **5001** (`firebase.json` `emulators`). |
| `SHOW_WIDGET_CATALOG` | `lib/main.dart` | No. Debug widget gallery. |

Android release signing (`android/key.properties`) is **not** required for
`flutter run`. Copy `android/key.properties.example` only when you ship a
signed release.

### 8. Run the app

Against **deployed** Firebase (after steps 4–6):

```bash
flutter run
```

Or pick a device:

```bash
flutter devices
flutter run -d <deviceId>
flutter run -d chrome
```

Against **local emulators** (optional):

```bash
cd functions
npm run build
cd ..
firebase emulators:start --only auth,functions,firestore
```

In another terminal:

```bash
flutter run --dart-define=USE_EMULATOR=true
```

Web + emulator: `flutter run -d chrome --dart-define=USE_EMULATOR=true`.
`lib/main.dart` disables Firestore persistence on web to avoid a known
IndexedDB/hot-restart crash.

### 9. iOS: HealthKit (macOS only)

Wearable sync on iPhone uses HealthKit (`lib/services/health_sync_service.dart`).
Usage strings are already in `ios/Runner/Info.plist`
(`NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`).
`ios/Runner/Runner.entitlements` already contains
`com.apple.developer.healthkit`.

You still must, **on a Mac, in Xcode**:

1. Open `ios/Runner.xcworkspace` (not the `.xcodeproj`).
2. **Signing & Capabilities** → add **HealthKit** for your team / bundle id
   (Apple Developer capability). This cannot be done from Windows or Linux.
3. Run on a **physical iPhone** for HealthKit / Apple Watch. The iOS simulator
   has no real HealthKit watch data.

Android wearables use Health Connect (permissions already in
`android/app/src/main/AndroidManifest.xml`). That path does not need Xcode.
Skipping device setup in the app is **Tier 3**: manual check-ins only.

### 10. How to verify it worked

1. **Sign up** as an **athlete** (email/password). Complete sport selection.
   You can **Skip** device connect (Tier 3).
2. **Log today** / **Log check-in** — duration, effort words, how you feel,
   sleep. Save. The client writes `athletes/{uid}/checkins/{yyyy-mm-dd}` and
   calls the `recalculateRisk` callable.
3. In Firebase Console → Firestore, open that athlete:
   - `checkins/{today}` exists.
   - `riskResults/latest` exists after the callable returns.
4. **Risk assessment:**
   - **Fewer than 5 check-in days** (35-day window): `latest` has
     `insufficientData: true` and `checkInCount` (`riskPipeline.ts`). That
     still proves Functions + rules are wired.
   - **5+ distinct days:** `latest` has `riskLevel` (`LOW` / `MEDIUM` /
     `HIGH`), `recommendationStatus: pending`, and related fields. The
     athlete does **not** see recommendation text until a coach
     **approves** or **sends** the plan.
5. Optional: create a **coach** account, link the athlete with the coach
   invite code, approve the plan — athlete **Alerts** should show the
   approval notice (push needs Cloud Messaging + notification permission).

If step 3 never appears, check Functions logs (`firebase functions:log`),
that Blaze is enabled, and that `ANTHROPIC_API_KEY` is bound if you expected
LLM prose (risk **level** does not need the key).

---

## Structure

- `lib/` — Flutter app (athlete + coach journeys)
- `functions/` — Firebase Cloud Functions: Training Load, ACWR,
  Fitness-Fatigue, rule-based Risk Model, sport-specific Recommendation
  Engine, and the Orchestrator that resolves risk-vs-performance conflicts
- `firestore.rules` — coach/athlete permission boundaries
- `firebase.json`, `firestore.indexes.json` — Firebase project config

## What's implemented (v0.2)

- Email/password auth with coach or athlete role
- Sport selection (Section 12.2's grouped list)
- Manual daily check-in (RPE, fatigue, sleep, soreness notes) — works
  with zero wearable hardware (Tier 3, Section 9)
- **Wearable sync** — Apple Health (iOS) and Health Connect (Android) for
  Tier 1/2; manual entry for Tier 3. Syncs on app open/resume.
- Server-side calculation of Training Load, ACWR, Fitness-Fatigue,
  and a rule-based risk classification (Section 13.4)
- Sport-specific, orchestrated recommendation (risk always outranks
  performance — Section 6)
- Coach roster, dashboard, approve / reject / modify flow
  (Human Approval Step — Section 6 / 11)
- **Ask AthleteIQ** — natural-language Q&A grounded in the athlete's last
  14 days of check-ins and latest risk result (`askAthleteIQ` callable;
  Claude via `ANTHROPIC_API_KEY`)
- **Knowledge Agent** — RAG-backed research notes written onto
  `riskResults/latest` during the risk pipeline; coach Supporting Research
  screen shows live output when present, otherwise Section 18.1 baseline
  citations
- Pain reports with LLM urgency triage, coach–athlete messaging, privacy
  settings, account deletion, and weekly reports

## Not built yet (see guide's Roadmap section)

- Garmin / Whoop integrations (requires vendor API approval)
- Trained ML classifiers (Section 14.6) — v1 uses transparent rules,
  which the doc itself says is the correct starting point
- Coach-override learning, competition calendar awareness
- Full store release (privacy policy hosting, Play/App Store listings, iOS
  signing)
