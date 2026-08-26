"""
Direct port of functions/src/calculations.ts — same formulas, same
thresholds, same variable names where possible, so behavior matches
exactly what your Cloud Function would have done.

Research-verified formulas (Section 18.1):
- Training Load = Duration x RPE (session-RPE method)
- ACWR = 7-day acute load / 28-day chronic average weekly load
- Fitness/Fatigue = Banister impulse-response model
"""
from __future__ import annotations
from dataclasses import dataclass
from typing import Optional
import math


@dataclass
class Entry:
    """One check-in, shaped exactly like the objects index.ts builds
    from Firestore docs before calling assessRisk()."""
    date: str
    training_load: Optional[float]
    sleep_hours: Optional[float]
    resting_heart_rate: Optional[float]
    hrv: Optional[float]
    fatigue_score: int


def sum_load(entries: list[Entry], days: int) -> float:
    """Sum of training load over the most recent N days (entries must
    already be sorted recent-first, matching index.ts's Firestore query)."""
    recent = entries[:days]
    return sum(e.training_load or 0 for e in recent)


def calculate_acwr(entries: list[Entry]) -> tuple[float, float, float]:
    """ACWR = acute (7-day sum) / chronic (28-day sum / 4). Gabbett (2016)
    sweet spot 0.8-1.3, danger zone >1.5 (Section 18.1/18.2, contested
    in the literature — always labeled as a signal, not a certainty)."""
    acute7 = sum_load(entries, 7)
    chronic28_sum = sum_load(entries, 28)
    chronic_avg_weekly = chronic28_sum / 4
    acwr = (acute7 / chronic_avg_weekly) if chronic_avg_weekly > 0 else 1.0
    return acwr, acute7, chronic_avg_weekly


def calculate_fitness_fatigue(entries_oldest_first: list[Entry]) -> tuple[float, float, float]:
    """Simplified Banister Fitness-Fatigue model. Fitness decays slowly
    (~42 day time constant), Fatigue decays quickly (~7 days).
    Performance = Fitness - Fatigue."""
    fitness_tau = 42
    fatigue_tau = 7
    fitness = 0.0
    fatigue = 0.0
    for e in entries_oldest_first:
        load = e.training_load or 0
        fitness = fitness * math.exp(-1 / fitness_tau) + load
        fatigue = fatigue * math.exp(-1 / fatigue_tau) + load
    return fitness, fatigue, fitness - fatigue


def _avg_of(nums: list[float]) -> float:
    return sum(nums) / len(nums) if nums else 0.0


def calculate_recovery_trend(entries_recent_first: list[Entry]) -> tuple[str, bool]:
    """HRV-based trend if the athlete's device provides it (Tier 1).
    Otherwise a rolling baseline from resting HR + sleep + fatigue
    (Section 9 — degrades gracefully rather than blocking)."""
    last7 = entries_recent_first[:7]
    prev7 = entries_recent_first[7:14]

    has_hrv = any(e.hrv is not None for e in last7) and any(e.hrv is not None for e in prev7)

    if has_hrv:
        recent = _avg_of([e.hrv for e in last7 if e.hrv is not None])
        prior = _avg_of([e.hrv for e in prev7 if e.hrv is not None])
        if prior == 0:
            return "stable", True
        change = (recent - prior) / prior
        if change > 0.05:
            return "improving", True
        if change < -0.05:
            return "worsening", True
        return "stable", True

    worse_votes = 0
    better_votes = 0

    rhr_recent = _avg_of([e.resting_heart_rate for e in last7 if e.resting_heart_rate is not None])
    rhr_prior = _avg_of([e.resting_heart_rate for e in prev7 if e.resting_heart_rate is not None])
    if rhr_recent and rhr_prior:
        if rhr_recent > rhr_prior * 1.03:
            worse_votes += 1
        elif rhr_recent < rhr_prior * 0.97:
            better_votes += 1

    sleep_recent = _avg_of([e.sleep_hours for e in last7 if e.sleep_hours is not None])
    sleep_prior = _avg_of([e.sleep_hours for e in prev7 if e.sleep_hours is not None])
    if sleep_recent and sleep_prior:
        if sleep_recent < sleep_prior - 0.5:
            worse_votes += 1
        elif sleep_recent > sleep_prior + 0.5:
            better_votes += 1

    fatigue_recent = _avg_of([e.fatigue_score for e in last7])
    fatigue_prior = _avg_of([e.fatigue_score for e in prev7])
    if fatigue_prior:
        if fatigue_recent > fatigue_prior + 0.4:
            worse_votes += 1
        elif fatigue_recent < fatigue_prior - 0.4:
            better_votes += 1

    if worse_votes > better_votes:
        return "worsening", False
    if better_votes > worse_votes:
        return "improving", False
    return "stable", False


def is_fatigue_persistent(entries_recent_first: list[Entry]) -> bool:
    """Is Fatigue staying elevated for several days instead of clearing? (Step 4)"""
    last4 = entries_recent_first[:4]
    if len(last4) < 4:
        return False
    return all(e.fatigue_score >= 4 for e in last4)
