/**
 * Ask AthleteIQ — LangChain + Anthropic chat, grounded in this athlete's
 * Firestore check-ins and latest risk result. Never invents numbers.
 *
 * Conversation history: athletes/{uid}/aiChat/{messageId}
 * (covered by firestore.rules match /aiChat/{messageId}).
 */

import { StringOutputParser } from '@langchain/core/output_parsers';
import { ChatPromptTemplate } from '@langchain/core/prompts';
import { DocumentData, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { DailyEntry } from './calculations';
import { createChatAnthropic } from './anthropic';
import {
  parsePrivacySettings,
  PrivacySettings,
  withheldLabels,
} from './privacySettings';
import { sportsLabel, wordingSport } from './athleteSports';
import {
  GROUNDING_INSTRUCTION,
  MEDICAL_DISCLAIMER,
  MEDICAL_ESCALATE,
  MISSING_METRIC_DISCLOSE,
} from './promptFragments';
import { phrasePerformance, PerformancePrediction, RiskAssessment } from './riskModel';

export interface ChatAnswer {
  text: string;
  source: 'llm' | 'fallback' | 'guard';
}

/** Polite decline used by the keyword pre-check (and as the LLM's target wording). */
export const OFF_TOPIC_REPLY =
  "I'm here to help with your training and health data — I can't help with that, but feel free to ask me about your recent check-ins, risk level, or recommendations.";

/**
 * Lightweight topic gate before Firestore/LLM work.
 * Allow list wins over deny list so app/training questions stay through.
 * Ambiguous questions (neither list) pass through; the system prompt declines them.
 */
const ON_TOPIC_RE =
  /\b(athlete\s*iq|athleteiq|this app|the app|how (does|do) (this|the|athlete)|risk|acwr|training|workout|session|load|sleep|fatigue|tired|recovery|hrv|heart\s*rate|rhr|check[\s-]?in|coach|recommend|pain|sore|injury|hurt|performance|readiness|rpe|rest day|wearable|hydration|nutrition|stretch|warm[\s-]?up|cool[\s-]?down|overreach|overtrain|deload|taper|race|match|practice|volume|intensity|soreness|doms|muscle|knee|shoulder|ankle|back pain|wellness|mood|stress|energy)\b/i;

const OFF_TOPIC_RE =
  /\b(weather|forecast|temperature|joke|funny|laugh|riddle|trivia|capital of|president|election|politic|stock|crypto|bitcoin|nft|movie|netflix|recipe|cooking|homework|lyrics|celebrity|gossip|horoscope|lottery|gambling)\b|\bwho (is|was|won)\b|\bcook\b|\bsolve this\b|\bwrite\b.{0,24}\b(poem|story|essay|song)\b/i;

export function isOnTopicQuestion(question: string): boolean {
  const q = question.trim();
  if (!q) return false;
  if (ON_TOPIC_RE.test(q)) return true;
  if (OFF_TOPIC_RE.test(q)) return false;
  // Ambiguous — let the LLM + system prompt decide.
  return true;
}

export const SYSTEM_PROMPT = `You are AthleteIQ AI, an in-app assistant inside a sports training platform. You answer an athlete's questions about their own training load, sleep, fatigue, recovery, performance, pain/injury triage (non-medical), coach recommendations, and how AthleteIQ itself works, using ONLY the data provided to you below when the question needs athlete numbers.

Scope:
- ON-TOPIC: this athlete's check-ins, risk level, ACWR, training load, sleep, fatigue, HRV, recovery, recommendations, Report Pain, wearables, and questions about what AthleteIQ is or how the app calculates risk / shows recommendations.
- OFF-TOPIC: general trivia, weather, jokes, recipes, homework, politics, finance, entertainment, or any advice unrelated to this athlete's training/health data or the app. For off-topic questions, reply with exactly this one sentence (and nothing else): "I'm here to help with your training and health data — I can't help with that, but feel free to ask me about your recent check-ins, risk level, or recommendations."

Rules:
- Keep answers short: 1-3 sentences, conversational, no headers or bullet lists.
- ${GROUNDING_INSTRUCTION} ${MISSING_METRIC_DISCLOSE}
- ${MEDICAL_DISCLAIMER} ${MEDICAL_ESCALATE}
- Never override or contradict the coach-approved recommendation; defer to it.
- If the data provided is insufficient to answer confidently, say so plainly.`;

export interface ChatContextExtras {
  recommendation?: string | null;
  recommendationStatus?: string | null;
  privacy?: PrivacySettings;
  forCoach?: boolean;
}

/** Turn the athlete's recent numbers into a compact text block for the model. */
export function buildChatContext(
  entriesRecentFirst: DailyEntry[],
  risk: RiskAssessment | null,
  sport: string | null | undefined,
  athleteName: string,
  extras: ChatContextExtras = {},
): string {
  const privacy = extras.privacy;
  const forCoach = extras.forCoach === true;
  const recReleased =
    forCoach ||
    extras.recommendationStatus === 'approved' ||
    extras.recommendationStatus === 'modified';
  const shareLoad = !forCoach || privacy?.trainingLogs !== false;
  const shareWearable = !forCoach || privacy?.wearableData !== false;
  const shareFatigue = !forCoach || privacy?.dailyFatigueCheckIn !== false;

  const last14 = entriesRecentFirst.slice(0, 14);
  const lines = [`Athlete: ${athleteName}`, `Sport: ${sport ?? 'unspecified'}`];

  if (forCoach && privacy) {
    const hidden = withheldLabels(privacy);
    if (hidden.length > 0) {
      lines.push(
        `PRIVACY: The athlete has not shared the following with their coach: ${hidden.join('; ')}. ` +
          'Do not mention, infer, or reconstruct those metrics.',
      );
    }
  }

  if (risk) {
    lines.push(`Current risk level: ${risk.riskLevel} (confidence: ${shareWearable ? risk.confidence : 'not shared'})`);
    if (shareLoad) {
      lines.push(`ACWR (acute:chronic workload ratio): ${risk.acwr.toFixed(2)}`);
      lines.push(`7-day training load: ${risk.trainingLoad7d.toFixed(0)}`);
      lines.push(`28-day avg weekly training load: ${risk.trainingLoad28dAvg.toFixed(0)}`);
    } else {
      lines.push('ACWR and training load: not shared with the coach');
    }
    if (shareWearable) {
      lines.push(`Recovery trend: ${risk.recoveryTrend}`);
    } else {
      lines.push('Recovery trend: not shared with the coach');
    }
    if (shareLoad) {
      lines.push(`Performance prediction: ${risk.performanceFrame} (${risk.performancePrediction})`);
    }
    if (shareLoad && shareWearable && shareFatigue && recReleased) {
      lines.push(`Coach-facing reason: ${risk.reason}`);
    }
  } else {
    lines.push('Current risk level: not enough check-in data yet');
  }

  if (risk && extras.recommendation && recReleased) {
    lines.push(`Latest recommendation: ${extras.recommendation}`);
    lines.push(`Recommendation status: ${extras.recommendationStatus ?? 'unknown'}`);
  }

  if (last14.length > 0) {
    lines.push('\nLast 14 days of check-ins (most recent first):');
    for (const e of last14) {
      const parts = [`  ${e.date}:`];
      if (shareFatigue) parts.push(`fatigue ${e.fatigueScore}/5`);
      else parts.push('fatigue not shared');
      if (shareWearable && e.sleepHours != null) parts.push(`sleep ${e.sleepHours.toFixed(1)}h`);
      if (shareLoad) {
        if (e.trainingLoad != null) parts.push(`training load ${e.trainingLoad.toFixed(0)}`);
        else parts.push('rest day');
      } else {
        parts.push('training load not shared');
      }
      if (shareWearable && e.hrv != null) parts.push(`HRV ${e.hrv.toFixed(0)}`);
      if (shareWearable && e.restingHeartRate != null) {
        parts.push(`resting HR ${e.restingHeartRate.toFixed(0)}`);
      }
      lines.push(parts.join(', '));
    }
  } else {
    lines.push('\nNo check-ins logged yet.');
  }

  return lines.join('\n');
}

/** Rule-based fallback when the LLM is unavailable. */
export function fallbackAnswer(question: string): string {
  const q = question.toLowerCase();
  if (/(fatigue|tired|exhausted)/.test(q)) {
    return (
      'I don\'t have a live model answer right now. Check your latest risk result ' +
      'and recent sleep/fatigue logs — that combination is usually why fatigue and risk go up.'
    );
  }
  if (/(train|workout|today|tomorrow)/.test(q)) {
    return "Check your latest coach-approved recommendation before today's session — follow that plan.";
  }
  if (/(pain|knee|hurt|sore)/.test(q)) {
    return "Please log this in Report Pain and flag it to your coach — I can't give medical advice.";
  }
  if (/(sleep|recovery)/.test(q)) {
    return "Aim for 7.5–8.5 hours of sleep tonight — it's your primary recovery lever against training fatigue.";
  }
  return 'AthleteIQ tracks your training load, recovery, and fatigue trends. Always follow your coach-approved plan.';
}

function buildChain(apiKey: string) {
  const model = createChatAnthropic({
    apiKey,
    maxTokens: 300,
  });

  const prompt = ChatPromptTemplate.fromMessages([
    ['system', SYSTEM_PROMPT],
    ['human', "Athlete data:\n{context}\n\nAthlete's question: {question}"],
  ]);

  return prompt.pipe(model).pipe(new StringOutputParser());
}

/**
 * Grounded LLM answer when ANTHROPIC_API_KEY is set; otherwise the
 * rule-based fallback. Never throws — always returns something usable.
 */
export async function generateAnswer(
  question: string,
  entriesRecentFirst: DailyEntry[],
  risk: RiskAssessment | null,
  sport: string | null | undefined,
  athleteName: string,
  extras: ChatContextExtras = {},
): Promise<ChatAnswer> {
  if (!isOnTopicQuestion(question)) {
    return { text: OFF_TOPIC_REPLY, source: 'guard' };
  }

  const apiKey = process.env.ANTHROPIC_API_KEY?.trim();
  const context = buildChatContext(entriesRecentFirst, risk, sport, athleteName, extras);

  if (!apiKey) {
    logger.warn('askAthleteIQ: ANTHROPIC_API_KEY missing, using fallback');
    return { text: fallbackAnswer(question), source: 'fallback' };
  }

  try {
    const chain = buildChain(apiKey);
    const text = (await chain.invoke({ context, question })).trim();
    if (!text) {
      return { text: fallbackAnswer(question), source: 'fallback' };
    }
    return { text, source: 'llm' };
  } catch (err) {
    logger.error('askAthleteIQ LangChain call failed', err);
    return { text: fallbackAnswer(question), source: 'fallback' };
  }
}

function checkInDateKey(id: string, data: DocumentData): string {
  if (/^\d{4}-\d{2}-\d{2}$/.test(id)) return id;
  const raw = data.date;
  if (raw && typeof raw.toDate === 'function') {
    return raw.toDate().toISOString().slice(0, 10);
  }
  return id;
}

function riskFromDoc(data: DocumentData | undefined): RiskAssessment | null {
  if (!data || data.insufficientData || !data.riskLevel) return null;
  const band = (data.performancePrediction ?? 'AVERAGE') as PerformancePrediction;
  const framed = phrasePerformance(undefined, band);
  return {
    riskLevel: data.riskLevel,
    confidence: data.confidence ?? '',
    reason: data.reason ?? '',
    acwr: Number(data.acwr ?? 0),
    trainingLoad7d: Number(data.trainingLoad7d ?? 0),
    trainingLoad28dAvg: Number(data.trainingLoad28dAvg ?? 0),
    recoveryTrend: data.recoveryTrend ?? 'stable',
    performancePrediction: band,
    performanceFrame: data.performanceFrame ?? framed.label,
    performanceFrameAxis: data.performanceFrameAxis ?? framed.axis,
  };
}

export interface AnswerAthleteQuestionInput {
  athleteUid: string;
  question: string;
  callerUid: string;
  callerName: string;
}

/**
 * Load last 14 days of check-ins + latest risk result, generate an answer,
 * persist both messages under athletes/{uid}/aiChat.
 * All Firestore reads are `athletes/{input.athleteUid}` — the model never
 * supplies an athlete id.
 * Clear off-topic questions skip check-in/risk reads (still verify the athlete exists).
 */
export async function answerAthleteQuestion(
  input: AnswerAthleteQuestionInput,
): Promise<ChatAnswer> {
  const db = getFirestore();
  const athleteRef = db.collection('athletes').doc(input.athleteUid);
  const athleteDoc = await athleteRef.get();
  if (!athleteDoc.exists) {
    throw new Error('Athlete profile not found.');
  }

  let answer: ChatAnswer;

  if (!isOnTopicQuestion(input.question)) {
    answer = { text: OFF_TOPIC_REPLY, source: 'guard' };
  } else {
    const athleteData = athleteDoc.data()!;
    const forCoach = input.callerUid !== input.athleteUid;
    const privacy = parsePrivacySettings(athleteData.privacySettings);

    const since = Timestamp.fromDate(new Date(Date.now() - 14 * 24 * 60 * 60 * 1000));
    const snap = await athleteRef
      .collection('checkins')
      .where('date', '>=', since)
      .orderBy('date', 'desc')
      .limit(14)
      .get();

    const entries: DailyEntry[] = snap.docs.map((d) => {
      const data = d.data();
      const durationMin = data.sessionDurationMinutes ?? 0;
      const rpe = data.rpe ?? 0;
      return {
        date: checkInDateKey(d.id, data),
        trainingLoad: durationMin * rpe,
        sleepHours: data.sleepHours ?? null,
        restingHeartRate: data.restingHeartRate ?? null,
        hrv: data.hrv ?? null,
        fatigueScore: data.fatigueScore ?? 3,
        sessionSport: typeof data.sessionSport === 'string' ? data.sessionSport : null,
        sessionSportGroup:
          typeof data.sessionSportGroup === 'string' ? data.sessionSportGroup : null,
      };
    });

    const riskSnap = await athleteRef.collection('riskResults').doc('latest').get();
    const riskData = riskSnap.data();
    const risk = riskFromDoc(riskData);

    answer = await generateAnswer(
      input.question,
      entries,
      risk,
      sportsLabel(athleteData) || wordingSport(athleteData, entries[0]).sport,
      athleteData.name || 'Athlete',
      {
        recommendation: riskData?.recommendation ?? null,
        recommendationStatus: riskData?.recommendationStatus ?? null,
        privacy,
        forCoach,
      },
    );
  }

  const chat = athleteRef.collection('aiChat');
  const askedAt = new Date();
  await chat.add({
    senderUid: input.callerUid,
    senderName: input.callerName,
    text: input.question,
    timestamp: askedAt.toISOString(),
    isAi: false,
    isCoach: input.callerUid !== input.athleteUid,
  });
  await chat.add({
    senderUid: 'athlete_iq_ai',
    senderName: 'AthleteIQ AI',
    text: answer.text,
    timestamp: new Date(askedAt.getTime() + 400).toISOString(),
    isAi: true,
    isCoach: false,
    source: answer.source,
  });

  return answer;
}
