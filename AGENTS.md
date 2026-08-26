# AGENTS.md — rules for AI coding agents

This file is the contract for any automated agent editing **AthleteIQ**. Follow it unless the user explicitly overrides a rule in the current task.

---

## Project shape

| Area | Path | Role |
|------|------|------|
| Flutter app | `lib/` | UI, client Firestore access, callable wrappers |
| **Active backend** | **`functions/src/`** | Risk pipeline, LLMs, privacy views, alerts, callables |
| Firestore rules | `firestore.rules` | Client read/write boundaries |
| Rules tests | `tests/firestore.rules.test.js` | Emulator-based security regressions |
| Architecture / demo | `docs/ARCHITECTURE.md`, `docs/DEMO_GUIDE.md` | System overview and live demo script |

Repo root **is** the Flutter project (`pubspec.yaml` here). There is no `mobile/` wrapper.

---

## 1. Backend: `functions/` only

- **All server logic lives in `functions/src/`** (TypeScript → `functions/lib/` via `tsc`).
- Deploy with Firebase (`firebase.json` points at `./functions`). Do **not** add or revive Python/FastAPI backends for production paths.
- New callables, triggers, and batch jobs belong in `functions/src/index.ts` and sibling modules — not in the Flutter app, not in archived folders.
- Shared client/server concepts: keep Dart models in `lib/models/` aligned with what Functions write; document shape changes (see §5).

---

## 2. `MODEL/` is archived — never build on it

- **`MODEL_prototype_do_not_use/`** (historically `MODEL/`) is an **archived FastAPI prototype**. It is **not** deployed, **not** called by the app, and **not** the source of truth for risk or LLM behavior.
- **Do not:** import from it, wire the Flutter app to it, copy logic from it without porting to `functions/`, deploy it, or expand its scope.
- **Do:** implement and fix production behavior in `functions/src/` (`riskModel.ts`, `riskPipeline.ts`, `calculations.ts`, etc.).

`backend_archive/` is similarly dead rollback material — ignore unless the user asks to restore it.

---

## 3. Risk and performance: deterministic only

**LLMs must never classify injury risk or performance bands.**

| Concern | Source of truth | LLM role |
|---------|-----------------|----------|
| `riskLevel` (LOW / MEDIUM / HIGH) | `assessRisk()` in `functions/src/riskModel.ts` | **None** — prose only via `explainabilityLlm.ts` |
| `performancePrediction` (GOOD / AVERAGE / DECLINING) | Same rule engine + `calculations.ts` | **None** — phrasing only |
| ACWR thresholds (1.5 / 1.3 / 0.8 band) | `calculations.ts` / `riskModel.ts` — **fixed**, not coach-tunable | **None** |
| Training **recommendation action** | Orchestrator may choose from an **allowed list**; on guardrail failure → `recommendationEngine.ts` fallback | Constrained choice, not free-form risk |

Rules when changing risk logic:

- Edit **`riskModel.ts`**, **`calculations.ts`**, and **`recommendationEngine.ts`** — not prompts alone.
- Add or update tests in **`functions/src/calculations.test.ts`** and **`functions/src/nonNegotiables.test.ts`** for threshold boundaries.
- Explainability LLM output is checked so it **cannot contradict** the locked `riskLevel` (`llmGuardrails.ts` + `explainabilityLlm.ts`).

---

## 4. LLM outputs: schema validation + deterministic fallback

Prompts asking for JSON are **not** a safety boundary. Every structured LLM path must:

1. **Parse** with shared helpers in **`functions/src/llmGuardrails.ts`** (Zod schemas).
2. **Apply business rules** after shape validation (e.g. no full training when risk is MEDIUM/HIGH; orchestrator action must be in the sport’s allowed list; no changing locked `riskLevel`).
3. **On any failure** — malformed JSON, wrong types, rule violation — **discard the LLM output** and use the **same deterministic fallback** as API/key failures (log via `logGuardrailFallback`).

Structured LLM surfaces (each has a schema + `apply*LlmResponse` or equivalent):

| Surface | Module |
|---------|--------|
| Orchestrator | `orchestratorAgent.ts` |
| Graded options | `gradedRecommendations.ts` |
| Explain | `explainabilityLlm.ts` |
| Research | `knowledgeAgent.ts` |
| Pain triage | `painUrgency.ts` |
| Sport classify | `sportClassifier.ts` |
| Weekly narrative | `weeklyReport.ts` |

**Ask AthleteIQ** (`aiChat.ts`) is free-text but still grounded and topic-gated — do not add JSON-only “classification” there.

When adding a **new** LLM call: add a Zod schema + business rules in `llmGuardrails.ts`, wire fallback to existing rule-based path, add cases to **`functions/src/llmGuardrails.test.ts`** (mock bad/violating responses, assert fallback — not happy path only).

Orchestrator **tools** must stay scoped to the session athlete (`orchestratorTools.ts` binds `boundAthleteId`; never trust model-supplied `athleteId` for Firestore paths).

Anthropic stack: `createChatAnthropic` in `anthropic.ts`; secrets via Firebase (`ANTHROPIC_API_KEY`).

---

## 5. Firestore shapes and privacy: tests required before “done”

A change is **not complete** until relevant tests pass.

### Document shape changes

If you add, rename, or remove fields on documents the app or Functions read/write:

- Update **Dart models** in `lib/models/` and **`FirestoreService`** usages if the Flutter client consumes the field.
- Update **Functions writers** (pipeline, privacy views, callables).
- Update **`ATHLETE_SUBCOLLECTIONS`** / delete-account lists in `functions/src/deleteAccount.ts` when adding athlete subcollections.
- Update **`docs/ARCHITECTURE.md`** only if the user asked for doc updates or the shape is architecturally significant.

### Privacy and approval

Human approval gate: new pipeline writes use `recommendationStatus: pending`; athletes see recommendation text only after **`approved`** or **`modified`** (`privacyViews.ts`, `lib/utils/approval_gate.dart`, `firestore.rules`).

| You touch… | You must run / update… |
|------------|-------------------------|
| `firestore.rules` | `tests/firestore.rules.test.js` (Firestore emulator) |
| `privacyViews.ts`, coach/athlete views, approval | `functions/src/privacyViews.test.js`, `recommendationGate.test.ts`, `nonNegotiables.test.ts` |
| `deleteAccount.ts` subcollection list | `deleteAccount.test.ts` |
| Check-in redaction / coach view | `privacyViews.test.ts`, rules tests for `checkinsCoachView` |
| Access control (who can read which athlete) | `athleteAccess.ts`, `nonNegotiables.test.ts`, rules tests |

### How to run tests

From **`functions/`** (PowerShell: use `;` not `&&`):

```bash
npm test
```

Includes: aiChat, privacyViews, deleteAccount, recommendationGate, promptFragments, evaluation, calculations, llmGuardrails, **nonNegotiables**.

Firestore rules (from repo root; requires JDK + Firebase CLI):

```bash
cd tests
firebase emulators:exec --config ../firebase.rules-test.json --only firestore "npm test"
```

Flutter widget/unit tests when you change `lib/` behavior:

```bash
flutter test
```

---

## 6. Non-negotiable product rules (do not regress)

Permanent regressions live in **`functions/src/nonNegotiables.test.ts`** and matching **`NON-NEGOTIABLE:`** cases in **`tests/firestore.rules.test.js`**:

- Athlete cannot read another athlete’s data; coach only sees roster athletes.
- ACWR boundary behavior at **1.5, 1.3, 0.8** (documented thresholds).
- Nightly alerts: risk spike, missed check-in, sync failure — correct recipients.
- Recommendations cannot reach the athlete without **`approved`** / **`modified`**.

If your change breaks these, fix the product — do not weaken the tests.

---

## 7. Implementation habits

- **Minimize scope.** Match existing naming, imports, and patterns in the file you edit.
- **Prompt fragments:** shared strings in `promptFragments.ts`; JSON examples in ChatPromptTemplate use `jsonExampleForChatPrompt()` (doubled braces).
- **No secrets in repo.** API keys via Firebase secrets / env — never commit.
- **Do not commit** unless the user explicitly asks. Do not force-push or skip hooks.
- **`functions/tsconfig.json`** has `noUnusedLocals` — build must stay clean.
- Prefer **`docs/ARCHITECTURE.md`** and **`docs/DEMO_GUIDE.md`** for onboarding context; do not duplicate long architecture prose in code comments.

---

## 8. Quick file map (common tasks)

| Task | Start here |
|------|------------|
| Risk after check-in | `riskPipeline.ts` → `recalculateRisk` in `index.ts` |
| ACWR / load windows | `calculations.ts` |
| Risk bands | `riskModel.ts` |
| Recommendation wording | `recommendationEngine.ts` |
| Coach approval / athleteView | `privacyViews.ts`, `firestore_service.dart` |
| LLM guardrails | `llmGuardrails.ts` |
| Callable auth | `athleteAccess.ts`, `requireAthleteOrCoach` in `index.ts` |
| Demo credentials | `lib/dev/demo_accounts.dart` |

When in doubt: production truth is **`functions/src/`**, not prompts alone and not **`MODEL_prototype_do_not_use/`**.
