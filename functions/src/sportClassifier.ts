/**
 * Section 12.2 — classify free-text "Other" sports into the nearest
 * sport group for recommendation templates. Uses LangChain + Anthropic
 * (Phase E2). Low confidence → sportGroup "other" (generic template).
 */

import { StringOutputParser } from '@langchain/core/output_parsers';
import { createChatAnthropic } from './anthropic';
import { ChatPromptTemplate } from '@langchain/core/prompts';
import { logger } from 'firebase-functions';
import { jsonExampleForChatPrompt } from './promptFragments';
import { SportGroup } from './recommendationEngine';
import { logGuardrailFallback, parseClassifyOutput } from './llmGuardrails';

export type SportClassificationConfidence = 'high' | 'low';

export interface SportClassificationResult {
  sport: string;
  sportGroup: SportGroup;
  confidence: SportClassificationConfidence;
  source: 'llm' | 'rules';
  groupLabel: string;
}

const GROUP_LABELS: Record<SportGroup, string> = {
  endurance: 'Endurance',
  teamContact: 'Team / Contact',
  strengthPower: 'Strength / Power',
  skillPrecision: 'Skill / Precision',
  combat: 'Combat',
  other: 'Other (generic)',
};

export const CLASSIFY_PROMPT = `You classify a free-text sport name into exactly one AthleteIQ sport group for training recommendations.

Groups (return the sportGroup id exactly):
- endurance — running, cycling, swimming, triathlon, rowing, hiking, ski endurance, etc.
- teamContact — field/court team sports with contact or intermittent high intensity (soccer, rugby, basketball, hockey, cricket, etc.)
- strengthPower — weightlifting, powerlifting, throwing, sprint field events, CrossFit-style strength work
- skillPrecision — racket sports, golf, gymnastics skill work, dance sport, precision timing sports
- combat — boxing, MMA, wrestling, judo, karate, fencing, etc.
- other — only if the sport truly does not fit any group OR you are unsure

Return JSON only:
${jsonExampleForChatPrompt('{"sportGroup":"endurance|teamContact|strengthPower|skillPrecision|combat|other","confidence":"high|low","reason":"one short sentence"}')}

Use confidence "high" only when the mapping is obvious. Use "low" when ambiguous, obscure, multi-discipline, or you would be guessing.`;

function ruleBasedClassify(sportText: string): SportClassificationResult {
  const text = sportText.toLowerCase();
  const sport = sportText.trim();

  const has = (...words: string[]) => words.some((w) => text.includes(w));

  if (
    has(
      'run',
      'marathon',
      'triathlon',
      'cycl',
      'bike',
      'swim',
      'row',
      'hik',
      'trail',
      'ultra',
      'xc ski',
      'cross country ski',
    )
  ) {
    return result(sport, 'endurance', 'high', 'rules');
  }
  if (
    has(
      'soccer',
      'football',
      'rugby',
      'basketball',
      'hockey',
      'volleyball',
      'netball',
      'cricket',
      'handball',
      'lacrosse',
      'water polo',
      'ultimate',
      'frisbee',
    )
  ) {
    return result(sport, 'teamContact', 'high', 'rules');
  }
  if (
    has(
      'weight',
      'powerlift',
      'strongman',
      'crossfit',
      'throw',
      'shot put',
      'discus',
      'hammer throw',
      'sprint',
      'jump',
    )
  ) {
    return result(sport, 'strengthPower', 'high', 'rules');
  }
  if (
    has(
      'tennis',
      'badminton',
      'squash',
      'golf',
      'pickleball',
      'table tennis',
      'ping pong',
      'archery',
      'bowling',
      'darts',
      'curling',
      'figure skat',
      'gymnast',
    )
  ) {
    return result(sport, 'skillPrecision', 'high', 'rules');
  }
  if (
    has(
      'box',
      'mma',
      'wrestl',
      'judo',
      'karate',
      'taekwondo',
      'muay',
      'bjj',
      'jiu',
      'fencing',
      'martial',
      'kickbox',
    )
  ) {
    return result(sport, 'combat', 'high', 'rules');
  }

  return result(sport, 'other', 'low', 'rules');
}

function result(
  sport: string,
  sportGroup: SportGroup,
  confidence: SportClassificationConfidence,
  source: 'llm' | 'rules',
): SportClassificationResult {
  const appliedGroup =
    confidence === 'low' || sportGroup === 'other' ? 'other' : sportGroup;
  return {
    sport,
    sportGroup: appliedGroup,
    confidence: confidence === 'high' && appliedGroup !== 'other' ? 'high' : 'low',
    source,
    groupLabel: GROUP_LABELS[appliedGroup],
  };
}

export function applyClassifyLlmResponse(
  raw: string,
  sportText: string,
): SportClassificationResult {
  const sport = sportText.trim();
  const parsed = parseClassifyOutput(raw);
  if (!parsed.ok) {
    logGuardrailFallback('classify', parsed.reason);
    return ruleBasedClassify(sport);
  }
  const group = parsed.data.sportGroup;
  if (parsed.data.confidence === 'low' || group === 'other') {
    return result(sport, 'other', 'low', 'llm');
  }
  return result(sport, group, 'high', 'llm');
}

/**
 * Classify free-text sport. Never throws — low confidence → other group.
 */
export async function classifyCustomSport(sportText: string): Promise<SportClassificationResult> {
  const sport = sportText.trim();
  if (!sport) {
    return result('Other', 'other', 'low', 'rules');
  }

  const apiKey = process.env.ANTHROPIC_API_KEY?.trim();
  if (!apiKey) {
    return ruleBasedClassify(sport);
  }

  try {
    const model = createChatAnthropic({ apiKey, maxTokens: 200 });
    const prompt = ChatPromptTemplate.fromMessages([
      ['system', CLASSIFY_PROMPT],
      ['human', 'Sport name entered by athlete: "{sport}"'],
    ]);
    const chain = prompt.pipe(model).pipe(new StringOutputParser());
    const raw = await chain.invoke({ sport });
    return applyClassifyLlmResponse(raw, sport);
  } catch (err) {
    logger.warn('sport classifier LLM failed; using rules fallback', err);
    return ruleBasedClassify(sport);
  }
}
