# AthleteIQ

A coach-approved training load / injury-risk assistant. See the full
build guide (`AthleteIQ_Build_Guide.md`) for step-by-step setup.

## Structure

- `lib/` — Flutter app (athlete + coach journeys)
- `functions/` — Firebase Cloud Functions: Training Load, ACWR,
  Fitness-Fatigue, rule-based Risk Model, sport-specific Recommendation
  Engine, and the Orchestrator that resolves risk-vs-performance conflicts
- `firestore.rules` — coach/athlete permission boundaries
- `firebase.json`, `firestore.indexes.json` — Firebase project config

## What's implemented (v1 / MVP)

- Email/password auth with coach or athlete role
- Sport selection (Section 12.2's grouped list)
- Manual daily check-in (RPE, fatigue, sleep, soreness notes) — works
  with zero wearable hardware (Tier 3, Section 9)
- Server-side calculation of Training Load, ACWR, Fitness-Fatigue,
  and a rule-based risk classification (Section 13.4)
- Sport-specific, orchestrated recommendation (risk always outranks
  performance — Section 6)
- Coach roster, dashboard, approve / reject / modify flow
  (Human Approval Step — Section 6 / 11)

## What's intentionally NOT built yet (see guide's Roadmap section)

- Wearable device sync (Garmin/Whoop/Apple Health APIs)
- Trained ML classifiers (Section 14.6) — v1 uses transparent rules,
  which the doc itself says is the correct starting point
- Knowledge Agent (pulling live sports-science research)
- Natural-language Q&A ("why am I tired this week?")
- Coach-override learning, graded recommendation options, competition
  calendar awareness
