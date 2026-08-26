# Do not use — early prototype

**This is an early prototype, not used in production.**

The real backend is **`functions/`** (Firebase Cloud Functions + Firestore). The Flutter app calls those callables (for example `recalculateRisk`, `askAthleteIQ`) — not this folder.

Contents under `athleteiq-risk-engine/` are a standalone Python/FastAPI experiment (including an old Render deploy path). Keep them for historical reference only. Do not wire the app to this code, deploy it, or treat it as the source of truth for risk logic.

Production risk, orchestrator, and LLM flows live in:

- `functions/src/riskModel.ts`
- `functions/src/riskPipeline.ts`
- `functions/src/recommendationEngine.ts`
