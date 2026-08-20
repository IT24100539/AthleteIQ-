# AthleteIQ

A coach-approved training load / injury-risk assistant. See the full
build guide (`AthleteIQ_Build_Guide.md`) for step-by-step setup.

> **Note:** This project uses `lib/` at the repo root and `functions/` as the
> single backend — see [`docs/repo_structure.md`](docs/repo_structure.md).

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


# AthleteIQ-
