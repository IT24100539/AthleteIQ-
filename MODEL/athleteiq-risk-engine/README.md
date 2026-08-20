# AthleteIQ Risk Engine — free-tier backend (Render)

This replaces your `functions/` Cloud Function with the exact same logic
running on Render's free tier instead of Firebase Blaze. $0 cost.

## What's in this folder

```
athleteiq_backend_free/
├── main.py                    ← FastAPI app, the /recalculate-risk endpoint
├── calculations.py             ← port of calculations.ts (ACWR, Fitness-Fatigue, etc.)
├── risk_model.py                ← port of riskModel.ts
├── recommendation_engine.py      ← port of recommendationEngine.ts
├── requirements.txt
└── render.yaml                    ← lets Render auto-configure the service
```

I tested `calculations.py` / `risk_model.py` / `recommendation_engine.py`
directly (not through the web server) with a simulated training-load spike,
and it correctly returned `MEDIUM` risk with a worsening recovery trend and
the right sport-worded recommendation — the math is verified, not guessed.

---

## Step 1 — Get a Firebase service account key

This is what lets the Python backend read/write your Firestore data
(the same permission Cloud Functions has automatically).

1. Firebase Console → your project (`athleteiq-app`) → gear icon → **Project settings**
2. **Service accounts** tab → **Generate new private key** → confirm
3. This downloads a `.json` file. **Never commit this file to git** — it's a secret credential, equivalent to a password.

## Step 2 — Push this folder to its own GitHub repo

Render deploys from a git repo, so this needs to live somewhere Render can see it.

```powershell
cd athleteiq_backend_free
git init
git add .
git commit -m "AthleteIQ risk engine - free tier backend"
```

Create an empty repo on GitHub (e.g. `athleteiq-risk-engine`), then:

```powershell
git remote add origin https://github.com/<your-username>/athleteiq-risk-engine.git
git branch -M main
git push -u origin main
```

**Important:** add a `.gitignore` with `serviceAccountKey.json` in it if you
ever save the key file locally in this folder, so it never accidentally
gets committed.

## Step 3 — Deploy on Render (free tier, no card required)

1. Go to https://render.com → sign up (GitHub login is easiest)
2. **New +** → **Blueprint**
3. Connect the `athleteiq-risk-engine` repo you just pushed — Render reads `render.yaml` automatically and pre-fills everything
4. It'll ask you to fill in `FIREBASE_SERVICE_ACCOUNT_JSON` — open the `.json` file you downloaded in Step 1, copy its **entire contents**, and paste it as the value. This is safe: Render stores it as a secret env var, not in your code or git history.
5. Click **Apply** / **Create Web Service**. First deploy takes 2-5 minutes.
6. Once live, Render gives you a URL like `https://athleteiq-risk-engine.onrender.com` — **copy this**, you'll need it in the Flutter app next.

**One free-tier quirk to know:** Render's free web services "spin down" after 15 minutes of no traffic, and the next request takes ~30-50 seconds to wake back up. For a class demo, hit the URL once a minute or two before you present so it's already warm. This doesn't affect correctness, just first-request speed.

## Step 4 — Update the Flutter app to call this instead of Cloud Functions

I've written the updated `firestore_service.dart` separately — see the main chat message. The short version: `submitCheckIn()` now does an `http.post()` to `https://athleteiq-risk-engine.onrender.com/recalculate-risk` with the athlete's Firebase ID token in the `Authorization: Bearer ...` header, instead of `httpsCallable('recalculateRisk')`.

## Step 5 — Test it

1. Run the FastAPI server's health check first — open `https://athleteiq-risk-engine.onrender.com/` in a browser, you should see `{"status":"ok","service":"AthleteIQ risk engine"}`
2. In your Flutter app, sign in as an athlete, submit a check-in
3. Check `AthleteHomeScreen` — should still correctly show the "coach reviewing" state (recommendationStatus starts as `pending`, same as before)
4. Sign in as the coach, open that athlete in `CoachDashboardScreen` — you should see the risk chip, ACWR, and reason text populated

If step 3/4 shows nothing, check the Render dashboard's **Logs** tab for that service — errors from `verify_id_token` or Firestore permission issues show up there in real time, same as `firebase functions:log` would have.

## Local testing before you deploy (optional but recommended)

```bash
pip install -r requirements.txt
export GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json   # path to the file from Step 1
uvicorn main:app --reload --port 8000
```

Then open http://127.0.0.1:8000/docs to test `/recalculate-risk` interactively (FastAPI auto-generates this page) before pushing to Render.
