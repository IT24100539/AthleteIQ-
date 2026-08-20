/**
 * Weekly report — structured stats from check-ins + optional LLM narrative.
 * Narrative is additive; numbers are computed server-side first.
 */

import { StringOutputParser } from '@langchain/core/output_parsers';
import { createChatAnthropic } from './anthropic';
import { ChatPromptTemplate } from '@langchain/core/prompts';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { calculateACWR, DailyEntry } from './calculations';
import { loadCheckIns } from './checkInLoader';
import {
  privacyAllShared,
  PrivacySettings,
} from './privacySettings';
import { wordingSport } from './athleteSports';
import { assessRisk } from './riskModel';

export interface WeeklyDailyLoad {
  date: string;
  load: number;
  fatigue: number;
}

export interface WeeklyReportResult {
  weekStart: string;
  weekEnd: string;
  weekLabel: string;
  sessionsCompleted: number;
  restDays: number;
  checkInsLogged: number;
  totalTrainingLoad: number;
  avgSleepHours: number | null;
  avgFatigue: number | null;
  peakAcwr: number | null;
  endAcwr: number | null;
  coachAdjustments: number;
  riskLevel: string | null;
  recoveryTrend: string | null;
  dailyLoads: WeeklyDailyLoad[];
  narrative: string;
  narrativeSource: 'llm' | 'rules';
}

const NARRATIVE_PROMPT = `You write a short weekly training summary for a coach reading AthleteIQ's "Week in review" screen.

Rules:
- 2–3 sentences, conversational, no bullet lists or headers.
- Use ONLY the numbers and labels provided below. Do not invent, estimate, or round values that are not given.
- If a metric is null or missing, do not mention it.
- Do not give medical advice or diagnose injury.
- Return JSON only: {"narrative":"..."}`;

function pad2(n: number): string {
  return String(n).padStart(2, '0');
}

export function toDateKey(d: Date): string {
  return `${d.getUTCFullYear()}-${pad2(d.getUTCMonth() + 1)}-${pad2(d.getUTCDate())}`;
}

export function getWeekRange(referenceDate: Date, weekOffset = 0): { start: Date; end: Date } {
  const d = new Date(
    Date.UTC(
      referenceDate.getUTCFullYear(),
      referenceDate.getUTCMonth(),
      referenceDate.getUTCDate(),
    ),
  );
  const day = d.getUTCDay();
  const diffToMonday = day === 0 ? -6 : 1 - day;
  const monday = new Date(d);
  monday.setUTCDate(d.getUTCDate() + diffToMonday + weekOffset * 7);
  const sunday = new Date(monday);
  sunday.setUTCDate(monday.getUTCDate() + 6);
  return { start: monday, end: sunday };
}

function formatWeekLabel(start: Date, end: Date): string {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  const s = `${months[start.getUTCMonth()]} ${start.getUTCDate()}`;
  const e = `${months[end.getUTCMonth()]} ${end.getUTCDate()}`;
  return `${s} – ${e}`;
}

function entriesUpTo(entriesRecentFirst: DailyEntry[], dateKey: string): DailyEntry[] {
  return entriesRecentFirst.filter((e) => e.date <= dateKey);
}

function entriesInRange(
  entriesRecentFirst: DailyEntry[],
  startKey: string,
  endKey: string,
): DailyEntry[] {
  return entriesRecentFirst.filter((e) => e.date >= startKey && e.date <= endKey);
}

function avgOf(values: number[]): number | null {
  if (values.length === 0) return null;
  return values.reduce((a, b) => a + b, 0) / values.length;
}

function enumerateDays(start: Date, end: Date): string[] {
  const keys: string[] = [];
  const cur = new Date(start);
  while (cur <= end) {
    keys.push(toDateKey(cur));
    cur.setUTCDate(cur.getUTCDate() + 1);
  }
  return keys;
}

function ruleBasedNarrative(data: Omit<WeeklyReportResult, 'narrative' | 'narrativeSource'>): string {
  const parts: string[] = [];
  parts.push(
    `${data.sessionsCompleted} training session${data.sessionsCompleted === 1 ? '' : 's'} logged across ${data.checkInsLogged} check-in${data.checkInsLogged === 1 ? '' : 's'}.`,
  );
  if (data.avgSleepHours != null) {
    parts.push(`Average sleep was ${data.avgSleepHours.toFixed(1)}h.`);
  }
  if (data.peakAcwr != null) {
    parts.push(`Peak ACWR reached ${data.peakAcwr.toFixed(2)}.`);
  }
  if (data.coachAdjustments > 0) {
    parts.push(
      `${data.coachAdjustments} coach plan adjustment${data.coachAdjustments === 1 ? '' : 's'} recorded this week.`,
    );
  } else if (data.riskLevel) {
    parts.push(`Risk ended the week at ${data.riskLevel}.`);
  }
  return parts.join(' ');
}

function parseNarrativeJson(raw: string): string | null {
  const trimmed = raw.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
  const start = trimmed.indexOf('{');
  const end = trimmed.lastIndexOf('}');
  if (start === -1 || end <= start) return null;
  try {
    const parsed = JSON.parse(trimmed.slice(start, end + 1)) as { narrative?: unknown };
    return typeof parsed.narrative === 'string' && parsed.narrative.trim()
      ? parsed.narrative.trim()
      : null;
  } catch {
    return null;
  }
}

function buildStatsContext(data: Omit<WeeklyReportResult, 'narrative' | 'narrativeSource'>): string {
  const lines = [
    `Week: ${data.weekLabel} (${data.weekStart} to ${data.weekEnd})`,
    `Sessions completed: ${data.sessionsCompleted}`,
    `Rest days logged: ${data.restDays}`,
    `Check-ins logged: ${data.checkInsLogged}`,
    `Total training load (session-RPE sum): ${data.totalTrainingLoad.toFixed(0)}`,
    `Average sleep hours: ${data.avgSleepHours != null ? data.avgSleepHours.toFixed(1) : 'not in data'}`,
    `Average fatigue (1–5): ${data.avgFatigue != null ? data.avgFatigue.toFixed(1) : 'not in data'}`,
    `Peak ACWR in week: ${data.peakAcwr != null ? data.peakAcwr.toFixed(2) : 'not in data'}`,
    `ACWR at week end: ${data.endAcwr != null ? data.endAcwr.toFixed(2) : 'not in data'}`,
    `Coach adjustments: ${data.coachAdjustments}`,
    `Risk level at week end: ${data.riskLevel ?? 'not in data'}`,
    `Recovery trend: ${data.recoveryTrend ?? 'not in data'}`,
    'Daily loads (date: load, fatigue):',
    ...data.dailyLoads.map((d) => `  ${d.date}: load ${d.load}, fatigue ${d.fatigue}/5`),
  ];
  return lines.join('\n');
}

async function generateNarrative(
  data: Omit<WeeklyReportResult, 'narrative' | 'narrativeSource'>,
): Promise<{ narrative: string; source: 'llm' | 'rules' }> {
  const fallback = ruleBasedNarrative(data);
  const apiKey = process.env.ANTHROPIC_API_KEY?.trim();
  if (!apiKey) {
    return { narrative: fallback, source: 'rules' };
  }

  try {
    const model = createChatAnthropic({ apiKey, maxTokens: 220 });
    const prompt = ChatPromptTemplate.fromMessages([
      ['system', NARRATIVE_PROMPT],
      ['human', '{stats}'],
    ]);
    const chain = prompt.pipe(model).pipe(new StringOutputParser());
    const raw = await chain.invoke({ stats: buildStatsContext(data) });
    const parsed = parseNarrativeJson(raw);
    if (!parsed) {
      logger.warn('weekly report: invalid LLM JSON, using rules fallback');
      return { narrative: fallback, source: 'rules' };
    }
    return { narrative: parsed, source: 'llm' };
  } catch (err) {
    logger.warn('weekly report LLM failed; using rules fallback', err);
    return { narrative: fallback, source: 'rules' };
  }
}

export async function buildWeeklyReport(
  athleteUid: string,
  weekOffset = 0,
): Promise<WeeklyReportResult> {
  const db = getFirestore();
  const { start, end } = getWeekRange(new Date(), weekOffset);
  const weekStart = toDateKey(start);
  const weekEnd = toDateKey(end);
  const weekLabel = formatWeekLabel(start, end);
  const weekKey = weekStart;

  const athleteSnap = await db.collection('athletes').doc(athleteUid).get();

  const entries = await loadCheckIns(athleteUid, 42);
  const weekEntries = entriesInRange(entries, weekStart, weekEnd);
  const weekLatest = weekEntries[0] ?? entries[0];
  const { sportGroup } = wordingSport(athleteSnap.data(), weekLatest);
  const dayKeys = enumerateDays(start, end);

  let peakAcwr: number | null = null;
  for (const dayKey of dayKeys) {
    const slice = entriesUpTo(entries, dayKey);
    if (slice.length < 5) continue;
    const { acwr } = calculateACWR(slice);
    if (peakAcwr == null || acwr > peakAcwr) peakAcwr = acwr;
  }

  const endSlice = entriesUpTo(entries, weekEnd);
  const endAcwr =
    endSlice.length >= 5 ? calculateACWR(endSlice).acwr : null;

  let riskLevel: string | null = null;
  let recoveryTrend: string | null = null;
  if (endSlice.length >= 5) {
    const assessment = assessRisk(endSlice, sportGroup);
    riskLevel = assessment.riskLevel;
    recoveryTrend = assessment.recoveryTrend;
  }

  const riskSnap = await db
    .collection('athletes')
    .doc(athleteUid)
    .collection('riskResults')
    .doc('latest')
    .get();
  const riskData = riskSnap.data();
  let coachAdjustments = 0;
  if (riskData?.reviewedAt && typeof riskData.reviewedAt === 'string') {
    const reviewed = riskData.reviewedAt.slice(0, 10);
    const status = riskData.recommendationStatus;
    if (
      reviewed >= weekStart &&
      reviewed <= weekEnd &&
      (status === 'approved' || status === 'modified')
    ) {
      coachAdjustments = 1;
    }
  }

  const loads = weekEntries.map((e) => e.trainingLoad ?? 0);
  const sessionsCompleted = loads.filter((l) => l > 0).length;
  const restDays = weekEntries.filter((e) => (e.trainingLoad ?? 0) === 0).length;
  const totalTrainingLoad = loads.reduce((a, b) => a + b, 0);
  const sleepVals = weekEntries
    .map((e) => e.sleepHours)
    .filter((v): v is number => v != null);
  const avgSleepHours = avgOf(sleepVals);
  const avgFatigue = weekEntries.length > 0 ? avgOf(weekEntries.map((e) => e.fatigueScore)) : null;

  const entryByDate = new Map(weekEntries.map((e) => [e.date, e]));
  const dailyLoads: WeeklyDailyLoad[] = dayKeys.map((date) => {
    const entry = entryByDate.get(date);
    return {
      date,
      load: entry?.trainingLoad ?? 0,
      fatigue: entry?.fatigueScore ?? 0,
    };
  });

  const stats: Omit<WeeklyReportResult, 'narrative' | 'narrativeSource'> = {
    weekStart,
    weekEnd,
    weekLabel,
    sessionsCompleted,
    restDays,
    checkInsLogged: weekEntries.length,
    totalTrainingLoad,
    avgSleepHours,
    avgFatigue,
    peakAcwr,
    endAcwr,
    coachAdjustments,
    riskLevel,
    recoveryTrend,
    dailyLoads,
  };

  const cacheRef = db
    .collection('athletes')
    .doc(athleteUid)
    .collection('weeklyReports')
    .doc(weekKey);
  const cached = await cacheRef.get();
  if (
    cached.exists &&
    cached.data()?.checkInsLogged === weekEntries.length &&
    typeof cached.data()?.narrative === 'string'
  ) {
    const c = cached.data()!;
    return {
      ...stats,
      narrative: c.narrative as string,
      narrativeSource: (c.narrativeSource as 'llm' | 'rules') ?? 'rules',
    };
  }

  const { narrative, source } = await generateNarrative(stats);
  const result: WeeklyReportResult = {
    ...stats,
    narrative,
    narrativeSource: source,
  };

  await cacheRef.set(
    {
      ...result,
      generatedAt: new Date().toISOString(),
    },
    { merge: true },
  );

  return result;
}

export function redactWeeklyReportForCoach(
  report: WeeklyReportResult,
  privacy: PrivacySettings,
): WeeklyReportResult {
  if (privacyAllShared(privacy)) return report;
  return {
    ...report,
    sessionsCompleted: privacy.trainingLogs ? report.sessionsCompleted : 0,
    restDays: privacy.trainingLogs ? report.restDays : 0,
    totalTrainingLoad: privacy.trainingLogs ? report.totalTrainingLoad : 0,
    avgSleepHours: privacy.wearableData ? report.avgSleepHours : null,
    avgFatigue: privacy.dailyFatigueCheckIn ? report.avgFatigue : null,
    peakAcwr: privacy.trainingLogs ? report.peakAcwr : null,
    endAcwr: privacy.trainingLogs ? report.endAcwr : null,
    recoveryTrend: privacy.wearableData ? report.recoveryTrend : null,
    dailyLoads: report.dailyLoads.map((d) => ({
      date: d.date,
      load: privacy.trainingLogs ? d.load : 0,
      fatigue: privacy.dailyFatigueCheckIn ? d.fatigue : 0,
    })),
    narrative:
      'Some metrics this week are not shared with you. Rows below omit withheld fields.',
    narrativeSource: 'rules',
  };
}
