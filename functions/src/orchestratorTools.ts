/**
 * Orchestrator tools — wrap riskModel.ts / calculations.ts.
 * The agent must call these; it does not receive precomputed scores.
 */

import {
  calculateFitnessFatigue,
  calculateRecoveryTrend,
  isFatiguePersistent,
} from './calculations';
import { CheckInLoader, loadCheckIns } from './checkInLoader';
import { wordingSport } from './athleteSports';
import { assessRisk } from './riskModel';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

export const ORCHESTRATOR_TOOL_DEFS = [
  {
    name: 'getRiskAssessment',
    description:
      "Return this athlete's current injury-risk assessment (ACWR, recovery, risk level). Does not include the performance prediction — call getPerformancePrediction for that.",
    schema: {
      type: 'object',
      properties: {
        athleteId: { type: 'string', description: 'Firebase athlete UID' },
      },
      required: ['athleteId'],
    },
  },
  {
    name: 'getPerformancePrediction',
    description:
      "Return this athlete's Banister Fitness–Fatigue performance band (GOOD / AVERAGE / DECLINING) plus the Section 12.3 sport-group phrasing of that same band. Independent of the risk level.",
    schema: {
      type: 'object',
      properties: {
        athleteId: { type: 'string', description: 'Firebase athlete UID' },
      },
      required: ['athleteId'],
    },
  },
  {
    name: 'getAthleteHistory',
    description:
      'Return the last N days of check-ins (training load, sleep, HRV, fatigue) most-recent first. Use when you need raw context beyond the summary scores.',
    schema: {
      type: 'object',
      properties: {
        athleteId: { type: 'string', description: 'Firebase athlete UID' },
        days: { type: 'number', description: 'How many days of history to return (5–35)' },
      },
      required: ['athleteId', 'days'],
    },
  },
];

async function sportGroupFor(athleteId: string): Promise<string> {
  try {
    const snap = await getFirestore().collection('athletes').doc(athleteId).get();
    const entries = await loadCheckIns(athleteId, 7);
    return wordingSport(snap.data(), entries[0]).sportGroup;
  } catch {
    return 'other';
  }
}

export async function getRiskAssessment(
  athleteId: string,
  loadEntries: CheckInLoader = loadCheckIns,
): Promise<string> {
  const entries = await loadEntries(athleteId, 35);
  if (entries.length < 5) {
    return JSON.stringify({ error: 'insufficient_data', checkInCount: entries.length });
  }
  const a = assessRisk(entries, await sportGroupFor(athleteId));
  return JSON.stringify({
    riskLevel: a.riskLevel,
    confidence: a.confidence,
    reason: a.reason,
    acwr: a.acwr,
    trainingLoad7d: a.trainingLoad7d,
    trainingLoad28dAvg: a.trainingLoad28dAvg,
    recoveryTrend: a.recoveryTrend,
    fatiguePersistent: isFatiguePersistent(entries),
  });
}

export async function getPerformancePrediction(
  athleteId: string,
  loadEntries: CheckInLoader = loadCheckIns,
): Promise<string> {
  const entries = await loadEntries(athleteId, 35);
  if (entries.length < 5) {
    return JSON.stringify({ error: 'insufficient_data', checkInCount: entries.length });
  }
  const a = assessRisk(entries, await sportGroupFor(athleteId));
  const ff = calculateFitnessFatigue(entries);
  const recovery = calculateRecoveryTrend(entries);
  return JSON.stringify({
    performancePrediction: a.performancePrediction,
    performanceFrame: a.performanceFrame,
    performanceFrameAxis: a.performanceFrameAxis,
    performanceIndex: ff.performanceIndex,
    fitness: ff.fitness,
    fatigue: ff.fatigue,
    recoveryTrend: recovery.trend,
    usedHRV: recovery.usedHRV,
  });
}

export async function getAthleteHistory(
  athleteId: string,
  days: number,
  loadEntries: CheckInLoader = loadCheckIns,
): Promise<string> {
  const window = Math.min(35, Math.max(5, Math.round(days)));
  const entries = await loadEntries(athleteId, window);
  return JSON.stringify({
    days: window,
    checkInCount: entries.length,
    entries: entries.slice(0, window).map((e) => ({
      date: e.date,
      trainingLoad: e.trainingLoad,
      sleepHours: e.sleepHours,
      restingHeartRate: e.restingHeartRate,
      hrv: e.hrv,
      fatigueScore: e.fatigueScore,
    })),
  });
}

/**
 * Tools always load `boundAthleteId` from the Orchestrator session.
 * The model's `athleteId` argument is ignored except to log a mismatch —
 * it must never be used as a Firestore path, or the agent could read
 * another athlete's check-ins.
 */
export async function invokeOrchestratorTool(
  name: string,
  args: Record<string, unknown>,
  loadEntries: CheckInLoader = loadCheckIns,
  boundAthleteId?: string,
): Promise<string> {
  const athleteId = (boundAthleteId ?? '').trim();
  if (!athleteId) {
    return JSON.stringify({ error: 'missing_bound_athleteId' });
  }
  const requested = String(args.athleteId ?? '').trim();
  if (requested && requested !== athleteId) {
    logger.warn('orchestrator tool: ignored athleteId that did not match the session athlete', {
      name,
      requested,
      boundAthleteId: athleteId,
    });
  }

  if (name === 'getRiskAssessment') {
    return getRiskAssessment(athleteId, loadEntries);
  }
  if (name === 'getPerformancePrediction') {
    return getPerformancePrediction(athleteId, loadEntries);
  }
  if (name === 'getAthleteHistory') {
    return getAthleteHistory(athleteId, Number(args.days ?? 14), loadEntries);
  }
  return JSON.stringify({ error: `Unknown tool: ${name}` });
}
