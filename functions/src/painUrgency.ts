/**
 * Pain-note urgency triage — LangChain + Anthropic (Phase E2).
 * Conservative: uncertainty is at least MEDIUM. Not a diagnosis.
 */

import { StringOutputParser } from '@langchain/core/output_parsers';
import { createChatAnthropic } from './anthropic';
import { ChatPromptTemplate } from '@langchain/core/prompts';
import { logger } from 'firebase-functions';

export type PainUrgency = 'LOW' | 'MEDIUM' | 'HIGH';

export interface PainAreaInput {
  location: string;
  severity: number;
}

export interface PainUrgencyResult {
  urgency: PainUrgency;
  reason: string;
  source: 'llm' | 'rules';
}

const TRIAGE_PROMPT = `You triage an athlete's pain report for their coach. This is a triage aid, NOT a medical diagnosis. Do not diagnose or recommend treatment.

Return JSON only:
{{"urgency":"LOW|MEDIUM|HIGH","reason":"one short sentence for the coach"}}

Conservative bias (follow strictly):
- If you are uncertain, the notes are vague, or something more serious cannot be ruled out, use at least MEDIUM. Never choose LOW when unsure.
- HIGH: cannot bear weight, locking/giving way, numbness/tingling, night pain that wakes them, sudden swelling, suspected fracture/dislocation, chest pain, faint/dizzy with pain, a pop/snap, or severity 5 with alarming language.
- MEDIUM: persistent or worsening pain, pain that changes training, moderate severity, unclear description, or any doubt.
- LOW: only when notes clearly describe mild, familiar, improving soreness or DOMS with no red-flag language.

Keep the reason factual and non-diagnostic.`;

const HIGH_KEYWORDS = [
  'can\'t walk',
  'cannot walk',
  'cant walk',
  'can\'t bear',
  'cannot bear',
  'numb',
  'tingl',
  'swell',
  'pop',
  'snap',
  'lock',
  'unstable',
  'gave way',
  'giving way',
  'night pain',
  'woke me',
  'wakes me',
  'fracture',
  'broken',
  'dislocat',
  'chest',
  'faint',
  'dizzy',
  'blacked out',
];

const MILD_KEYWORDS = ['sore', 'tight', 'doms', 'stiff', 'ache', 'aching'];

function maxSeverity(areas: PainAreaInput[]): number {
  return areas.reduce((max, a) => Math.max(max, a.severity), 0);
}

function hasAny(text: string, words: string[]): boolean {
  return words.some((w) => text.includes(w));
}

/**
 * Rule fallback — defaults to MEDIUM unless the report is clearly mild.
 */
export function ruleBasedPainUrgency(
  note: string,
  areas: PainAreaInput[],
): PainUrgencyResult {
  const text = note.toLowerCase();
  const severity = maxSeverity(areas);

  if (severity >= 5 || hasAny(text, HIGH_KEYWORDS)) {
    return {
      urgency: 'HIGH',
      reason: 'Flagged from severity or red-flag wording in the notes (rule triage).',
      source: 'rules',
    };
  }

  if (severity >= 4) {
    return {
      urgency: 'HIGH',
      reason: 'Severity 4+ is treated as HIGH until a coach reviews it.',
      source: 'rules',
    };
  }

  const clearlyMild =
    severity <= 2 &&
    (note.trim() === '' || hasAny(text, MILD_KEYWORDS)) &&
    !hasAny(text, HIGH_KEYWORDS);

  if (clearlyMild) {
    return {
      urgency: 'LOW',
      reason: 'Mild soreness with no red-flag language.',
      source: 'rules',
    };
  }

  return {
    urgency: 'MEDIUM',
    reason: 'Unclear or moderate report — flagged MEDIUM so a coach can review.',
    source: 'rules',
  };
}

function parseTriageJson(raw: string): {
  urgency: PainUrgency;
  reason: string;
} | null {
  const trimmed = raw.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
  const start = trimmed.indexOf('{');
  const end = trimmed.lastIndexOf('}');
  if (start === -1 || end <= start) return null;
  try {
    const parsed = JSON.parse(trimmed.slice(start, end + 1)) as {
      urgency?: string;
      reason?: string;
    };
    const urgency = String(parsed.urgency ?? '').toUpperCase();
    if (urgency !== 'LOW' && urgency !== 'MEDIUM' && urgency !== 'HIGH') {
      return null;
    }
    return {
      urgency,
      reason:
        typeof parsed.reason === 'string' && parsed.reason.trim()
          ? parsed.reason.trim()
          : 'Triage flag for coach review.',
    };
  } catch {
    return null;
  }
}

/**
 * Classify pain notes. Never throws — conservative rule fallback on failure.
 * Uncertainty from the LLM is raised to at least MEDIUM.
 */
export async function classifyPainUrgency(
  note: string,
  areas: PainAreaInput[],
): Promise<PainUrgencyResult> {
  const apiKey = process.env.ANTHROPIC_API_KEY?.trim();
  if (!apiKey) {
    return ruleBasedPainUrgency(note, areas);
  }

  const areaLines = areas
    .map((a) => `${a.location} (severity ${a.severity}/5)`)
    .join('; ');

  try {
    const model = createChatAnthropic({ apiKey, maxTokens: 200 });
    const prompt = ChatPromptTemplate.fromMessages([
      ['system', TRIAGE_PROMPT],
      [
        'human',
        'Body areas: {areas}\nAthlete notes: {note}',
      ],
    ]);
    const chain = prompt.pipe(model).pipe(new StringOutputParser());
    const raw = await chain.invoke({
      areas: areaLines || 'none listed',
      note: note.trim() || '(no free-text notes)',
    });
    const parsed = parseTriageJson(raw);
    if (!parsed) {
      logger.warn('pain urgency: invalid LLM JSON, using rules fallback');
      return ruleBasedPainUrgency(note, areas);
    }

    // Conservative: never accept LOW if the model sounded unsure,
    // or if rules would have raised it higher.
    const rules = ruleBasedPainUrgency(note, areas);
    let urgency = parsed.urgency;
    if (urgency === 'LOW' && rules.urgency !== 'LOW') {
      urgency = rules.urgency;
    }
    if (urgency === 'LOW' && note.trim() === '' && maxSeverity(areas) >= 3) {
      urgency = 'MEDIUM';
    }

    return {
      urgency,
      reason: parsed.reason,
      source: 'llm',
    };
  } catch (err) {
    logger.warn('pain urgency LLM failed; using rules fallback', err);
    return ruleBasedPainUrgency(note, areas);
  }
}
