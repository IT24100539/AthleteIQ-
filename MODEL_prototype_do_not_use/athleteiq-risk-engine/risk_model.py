"""
Direct port of functions/src/riskModel.ts — Section 13.4, Steps 5/6.
Same branches, same thresholds, same reasons text pattern.
"""
from __future__ import annotations
from dataclasses import dataclass
from calculations import (
    Entry,
    calculate_acwr,
    calculate_recovery_trend,
    is_fatigue_persistent,
    calculate_fitness_fatigue,
)


@dataclass
class RiskAssessment:
    risk_level: str  # LOW | MEDIUM | HIGH
    confidence: str
    reason: str
    acwr: float
    training_load_7d: float
    training_load_28d_avg: float
    recovery_trend: str
    performance_prediction: str  # GOOD | AVERAGE | DECLINING


def _capitalize(s: str) -> str:
    return s[0].upper() + s[1:] if s else s


def assess_risk(entries_recent_first: list[Entry]) -> RiskAssessment:
    acwr, acute7, chronic_avg_weekly = calculate_acwr(entries_recent_first)
    recovery_trend, used_hrv = calculate_recovery_trend(entries_recent_first)
    fatigue_persistent = is_fatigue_persistent(entries_recent_first)

    entries_oldest_first = list(reversed(entries_recent_first))
    _, _, performance_index = calculate_fitness_fatigue(entries_oldest_first)

    reasons: list[str] = []

    if acwr > 1.5 and recovery_trend == "worsening" and fatigue_persistent:
        risk_level = "HIGH"
        reasons.append(f"training load spiked (ACWR {acwr:.2f}, above the 1.5 danger threshold)")
        reasons.append("recovery is trending worse")
        reasons.append("fatigue has stayed elevated for several days")
    elif 0.8 <= acwr <= 1.3 and recovery_trend == "stable":
        risk_level = "LOW"
        reasons.append(f"training load is in the stable range (ACWR {acwr:.2f})")
        reasons.append("recovery looks stable")
    else:
        risk_level = "MEDIUM"
        if acwr > 1.3:
            reasons.append(f"training load is climbing (ACWR {acwr:.2f})")
        if recovery_trend == "worsening":
            reasons.append("recovery is trending down")
        if fatigue_persistent:
            reasons.append("fatigue has been elevated the last few days")
        if not reasons:
            reasons.append("signals are mixed and don't clearly fall in the low-risk range")

    if performance_index > 0 and recovery_trend != "worsening":
        performance_prediction = "GOOD"
    elif performance_index < 0 or fatigue_persistent:
        performance_prediction = "DECLINING"
    else:
        performance_prediction = "AVERAGE"

    confidence = "High (HRV available)" if used_hrv else "Medium (HRV not available for this athlete)"

    return RiskAssessment(
        risk_level=risk_level,
        confidence=confidence,
        reason=_capitalize("; ".join(reasons)) + ".",
        acwr=acwr,
        training_load_7d=acute7,
        training_load_28d_avg=chronic_avg_weekly,
        recovery_trend=recovery_trend,
        performance_prediction=performance_prediction,
    )
