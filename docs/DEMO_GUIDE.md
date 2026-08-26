# AthleteIQ — Live demo guide

Step-by-step walkthrough for **athlete → coach → athlete**: check-in, risk assessment, coach approval, athlete sees the plan, Ask AthleteIQ.

**Time:** ~15–20 minutes with pre-seeded demo accounts; ~25–30 if you sign up fresh (need 5+ check-ins for risk).

**Prerequisites:** App built and pointed at your Firebase project; Cloud Functions deployed with `ANTHROPIC_API_KEY` set (LLM steps fall back to rules if missing, but the demo is richer with the key live). Use a **debug build** to see demo shortcuts on the sign-in screen.

---

## Demo accounts (recommended)

Pre-seeded in Firebase for demos. Shown on the sign-in screen in debug mode (`lib/dev/demo_accounts.dart`).

| Role | Email | Password | Display name |
|------|--------|----------|----------------|
| **Athlete** | `demo.athlete@athleteiq.app` | `Demo1234!` | Alex Rivera |
| **Coach** | `demo.coach@athleteiq.app` | `Demo1234!` | Jordan Hale |

**Coach invite code** (for linking a *new* athlete to this coach): **`DEMO26`**

**Fastest login (debug build):** Sign-in screen → **Open demo athlete** / **Open demo coach** (seeds data if needed, then signs in).

Alex is already linked to Jordan and has check-in history, so risk and pending/approved flows work immediately.

---

## Demo script (pre-seeded accounts)

### Part 1 — Athlete: sign in and context

1. Launch the app → **Sign in as Athlete**.
2. Tap **Open demo athlete** (or enter `demo.athlete@athleteiq.app` / `Demo1234!`).
3. **Home** (`AthleteHomeScreen`): note **TODAY** card, ACWR, risk level, and whether the plan says *“Your coach is reviewing today's plan”* (pending) or shows an actual recommendation (already approved).
4. Optional: **Injury risk** / **My performance** for charts and locked risk explanation.

**Talking point:** Scores (ACWR, risk band) are visible to the athlete; **training recommendation text** stays hidden until the coach releases it.

---

### Part 2 — Athlete: submit a check-in (triggers risk pipeline)

1. From home → **Log today** (or **Manual daily log** / check-in flow).
2. Enter realistic values, e.g.:
   - Trained today: yes  
   - Duration ~45 min, RPE ~6–7  
   - Fatigue 3–4, sleep ~7 h  
3. **Save**.

**What happens behind the scenes:**

- Check-in written to `athletes/{uid}/checkins/{today}`.
- App calls **`recalculateRisk`**.
- Functions run rule-based risk + LLM enrichments → `riskResults/latest` (**pending**) + updated `athleteView`.

4. Return to **Home**. If the coach has not approved yet, **TODAY** should still say the coach is reviewing the plan (not the new recommendation text).

**Talking point:** The athlete sees updated **risk metrics** but not the unreleased **plan**.

---

### Part 3 — Coach: review and approve

1. Sign out → **Sign in as Coach** → **Open demo coach** (or `demo.coach@athleteiq.app` / `Demo1234!`).
2. **Roster** → open **Alex Rivera**.
3. **Coach dashboard** for Alex:
   - Risk level, ACWR, orchestrator recommendation, **graded options** (Conservative / Moderate / Minimal change).
   - Banner: *“The athlete cannot see this plan until you approve, modify, or reject it.”*
4. Choose one:
   - **Approve** — send primary recommendation as-is, or  
   - Tap a **graded option** card to approve that tier’s action, or  
   - **Send to athlete** with edited text (**modified**).
5. Confirm snackbar / status shows **approved** or **modified**.

**Talking point:** Human approval is mandatory; the pipeline always writes `pending` first.

---

### Part 4 — Athlete: see the approved plan

1. Sign back in as **demo athlete**.
2. Open **Home** → **TODAY** should now show the **released recommendation** and reason (not the “reviewing” placeholder).
3. Optional: **This week** card and **Ask AthleteIQ** now have an approved plan in context.

---

### Part 5 — Ask AthleteIQ

1. Still as athlete → open **Ask AthleteIQ** (from home or navigation).
2. Ask a grounded question, for example:
   - *“Why is my risk level what it is today?”*
   - *“Should I follow today’s recommendation?”*
   - *“How was my sleep and load this week?”*
3. Wait for the reply (callable **`askAthleteIQ`** → Claude, grounded in last 14 days of check-ins + risk; messages stored under `aiChat/`).

**Talking point:** Answers use **logged data only**; off-topic questions get a polite decline. The assistant defers to the **coach-approved** plan when relevant.

---

## Alternate path: fresh sign-up (optional)

Use this to show onboarding end-to-end. Risk needs **at least 5 check-ins** before `recalculateRisk` returns a full assessment.

### Athlete

1. Sign-in → **New Athlete? Create account** → complete onboarding slides → sign up (any email/password).
2. Pick sport (or **Other** → triggers **`classifyCustomSport`**).
3. Device step → continue (manual tier is fine).
4. **Connect coach** → enter invite code **`DEMO26`** (after coach account exists) or skip and link later from profile.
5. Log **5+ days** of check-ins (manual log daily, or import if available).
6. After the 5th save, home should show risk; recommendation stays **pending** until coach acts.

### Coach

1. **New Coach? Create account** → sign up.
2. **Roster** or **Settings** → copy **invite code** (demo coach uses `DEMO26`).
3. When athlete appears on roster, follow **Part 3** above.

---

## Demo checklist

| Step | Who | What to show |
|------|-----|----------------|
| 1 | Athlete | Sign in (demo buttons or credentials) |
| 2 | Athlete | Submit check-in → risk refresh, plan still gated |
| 3 | Coach | Dashboard → pending rec + graded options |
| 4 | Coach | Approve or modify → send to athlete |
| 5 | Athlete | Home shows approved **TODAY** plan |
| 6 | Athlete | Ask AthleteIQ grounded question |

---

## Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| “Building your first forecast” / no risk | Fewer than 5 check-ins |
| Check-in saved but risk unchanged | `recalculateRisk` failed — check Functions logs / deploy |
| Ask AthleteIQ generic fallback | Callable unreachable or no API key; check network and Functions |
| Coach sees no athletes | Athlete not linked (`coachUid`); use invite `DEMO26` |
| Athlete never sees plan | Coach must set status to **approved** or **modified**, not leave **pending** |
| Demo buttons missing | Not a **debug** build (`kDebugMode`) |

---

## Related docs

- `docs/ARCHITECTURE.md` — system diagram, Firestore layout, LLM roles
- `lib/dev/demo_accounts.dart` — canonical demo credentials
- `functions/scripts/e2eCheckin.js` — headless check-in + risk smoke test against demo accounts
