"""
Free-tier replacement for functions/src/index.ts's recalculateRisk
Cloud Function. Same job, same auth rules, same Firestore reads/writes —
just running on Render/Railway's free tier instead of Firebase Blaze.

How the Flutter app talks to this:
  Instead of `httpsCallable('recalculateRisk').call({'athleteUid': uid})`,
  FirestoreService.submitCheckIn() sends an HTTP POST to /recalculate-risk
  with the athlete's Firebase ID token in the Authorization header. This
  service verifies that token with Firebase Admin (same as Cloud Functions
  does automatically), so a client still can't spoof another user's uid —
  the "can't be spoofed" property from Section 13 is preserved.

Run locally:
  pip install -r requirements.txt
  export GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json
  uvicorn main:app --reload --port 8000

Deploy: see README.md in this folder.
"""
from __future__ import annotations
import os
import json
from datetime import datetime, timedelta, timezone

import firebase_admin
from firebase_admin import auth as fb_auth, credentials, firestore
from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from calculations import Entry
from risk_model import assess_risk
from recommendation_engine import build_recommendation

# ---------- Firebase Admin init ----------
if not firebase_admin._apps:
    raw_json = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON")
    if raw_json:
        cred = credentials.Certificate(json.loads(raw_json))
    else:
        cred = credentials.ApplicationDefault()
    firebase_admin.initialize_app(cred)

db = firestore.client()

app = FastAPI(title="AthleteIQ Risk Engine (free-tier backend)")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class RecalculateBody(BaseModel):
    athleteUid: str


@app.get("/")
def root():
    return {"status": "ok", "service": "AthleteIQ risk engine"}


@app.post("/recalculate-risk")
def recalculate_risk(body: RecalculateBody, authorization: str = Header(default="")):
    # ---- 1. Verify the caller's identity ----
    if not authorization.startswith("Bearer "):
        raise HTTPException(401, "Sign in required.")
    id_token = authorization.removeprefix("Bearer ").strip()
    try:
        decoded = fb_auth.verify_id_token(id_token)
    except Exception:
        raise HTTPException(401, "Invalid or expired sign-in token.")
    caller_uid = decoded["uid"]

    athlete_uid = body.athleteUid
    if not athlete_uid:
        raise HTTPException(400, "athleteUid is required.")

    # ---- 2. Load the athlete profile ----
    athlete_ref = db.collection("athletes").document(athlete_uid)
    athlete_doc = athlete_ref.get()
    if not athlete_doc.exists:
        raise HTTPException(404, "Athlete profile not found.")
    athlete_data = athlete_doc.to_dict() or {}

    # ---- 3. Only the athlete themself, or their assigned coach, may trigger this ----
    is_self = caller_uid == athlete_uid
    is_coach = caller_uid == athlete_data.get("coachUid")
    if not is_self and not is_coach:
        raise HTTPException(403, "Not authorized for this athlete.")

    # ---- 4. Pull the last 35 days of check-ins, newest first ----
    since = datetime.now(timezone.utc) - timedelta(days=35)
    checkins_query = (
        athlete_ref.collection("checkins")
        .where("date", ">=", since)
        .order_by("date", direction=firestore.Query.DESCENDING)
        .stream()
    )

    entries: list[Entry] = []
    for doc in checkins_query:
        data = doc.to_dict() or {}
        duration_min = data.get("sessionDurationMinutes")
        rpe = data.get("rpe")
        training_load = float(duration_min * rpe) if duration_min is not None and rpe is not None else None
        entries.append(
            Entry(
                date=doc.id,
                training_load=training_load,
                sleep_hours=data.get("sleepHours"),
                resting_heart_rate=data.get("restingHeartRate"),
                hrv=data.get("hrv"),
                fatigue_score=data.get("fatigueScore", 3),
            )
        )

    result_ref = athlete_ref.collection("riskResults").document("latest")

    # ---- 5. "Not enough data" empty state — never fabricate a score ----
    # TEMPORARY for testing — change this back to 5 before submitting the project!
    if len(entries) < 1:
        result_ref.set(
            {"insufficientData": True, "checkInCount": len(entries)}, merge=True
        )
        return {"status": "insufficient_data", "checkInCount": len(entries)}

    # ---- 6. Run the models ----
    assessment = assess_risk(entries)
    sport_group = athlete_data.get("sportGroup", "other")
    recommendation = build_recommendation(
        assessment.risk_level, assessment.performance_prediction, sport_group
    )

    # ---- 7. Human Approval Step — every recalculation resets to 'pending' ----
    result_ref.set(
        {
            "riskLevel": assessment.risk_level,
            "confidence": assessment.confidence,
            "reason": f"{assessment.reason} {recommendation.orchestrator_note}",
            "acwr": assessment.acwr,
            "trainingLoad7d": assessment.training_load_7d,
            "trainingLoad28dAvg": assessment.training_load_28d_avg,
            "recoveryTrend": assessment.recovery_trend,
            "performancePrediction": assessment.performance_prediction,
            "recommendation": recommendation.action,
            "recommendationStatus": "pending",
            "insufficientData": False,
            "calculatedAt": datetime.now(timezone.utc).isoformat(),
        }
    )

    return {"status": "ok", "riskLevel": assessment.risk_level}