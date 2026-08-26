"""
Direct port of functions/src/recommendationEngine.ts — Section 15.3.
SPORT_TEMPLATES keys match Dart's SportGroup enum .name values exactly
(endurance, teamContact, strengthPower, skillPrecision, combat, other)
since that's the string Firestore stores in athletes/{uid}.sportGroup.
"""
from __future__ import annotations
from dataclasses import dataclass

SPORT_TEMPLATES = {
    "endurance": {
        "HIGH": "Easy recovery session only, no intervals or race-pace work this week.",
        "MEDIUM": "Keep the volume but drop the intensity — easy pace, skip the hard set.",
        "LOW": "Continue training as planned.",
    },
    "teamContact": {
        "HIGH": "No contact training today — light conditioning only, sit out scrimmage.",
        "MEDIUM": "Train, but reduce contact drills and live reps today.",
        "LOW": "Continue training as planned.",
    },
    "strengthPower": {
        "HIGH": "Skip today's heavy session — light technical work or full rest.",
        "MEDIUM": "Reduce load 15-20% on today's lifts, keep technique sharp.",
        "LOW": "Continue training as planned.",
    },
    "skillPrecision": {
        "HIGH": "Light footwork/technical work only — no match play today.",
        "MEDIUM": "Reduce match intensity, add more recovery between games.",
        "LOW": "Continue training as planned.",
    },
    "combat": {
        "HIGH": "No sparring today — mobility and technical drilling only.",
        "MEDIUM": "Light sparring only, reduce rounds and contact intensity.",
        "LOW": "Continue training as planned.",
    },
    "other": {
        "HIGH": "Reduce training volume by 20% this week, add one extra rest day.",
        "MEDIUM": "Keep training but reduce intensity slightly.",
        "LOW": "Continue training as planned.",
    },
}


@dataclass
class Recommendation:
    action: str
    orchestrator_note: str


def build_recommendation(risk_level: str, performance_prediction: str, sport_group: str) -> Recommendation:
    """Section 6 (Orchestrator) + 15.2 — risk always outranks performance."""
    template = SPORT_TEMPLATES.get(sport_group, SPORT_TEMPLATES["other"])

    if risk_level in ("HIGH", "MEDIUM"):
        note = (
            "Performance looked strong this week, but risk takes priority — "
            "protecting the athlete comes first."
            if performance_prediction == "GOOD"
            else "Risk signals took priority in this decision."
        )
        return Recommendation(action=template[risk_level], orchestrator_note=note)

    # LOW risk: performance prediction breaks the tie (Section 15.2 Step 3).
    if performance_prediction == "DECLINING":
        return Recommendation(
            action="Consider a small deload — check in on sleep and fatigue trends.",
            orchestrator_note="Risk is low, but performance is trending down — worth a light check-in.",
        )

    return Recommendation(
        action=template["LOW"],
        orchestrator_note="Risk is low and performance looks on track.",
    )
