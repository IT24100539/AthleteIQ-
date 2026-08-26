/**
 * Shared LLM prompt clauses.
 *
 * Every system prompt that needs a safety or grounding rule imports it from
 * here so wording cannot drift. Do not hand-write a local paraphrase.
 *
 * Grounding style (intentional split, not an oversight):
 * - Orchestrator: tool-based. The model must call getRiskAssessment,
 *   getPerformancePrediction, and optionally getAthleteHistory. Numbers come
 *   from tool JSON, not a pasted context block.
 * - Every other number-using prompt: pasted-context. Metrics are injected in
 *   the human message. The model must not invent beyond that block.
 *
 * Brace escaping: ChatPromptTemplate treats `{foo}` as a template variable.
 * Always pass literal JSON examples through jsonExampleForChatPrompt().
 * SystemMessage prompts (Orchestrator, Knowledge Agent) keep single braces.
 */

/** Canonical "don't invent numbers" sentence. */
export const GROUNDING_INSTRUCTION =
  'Do not invent, estimate, or round numbers that are not in the provided data.';

/**
 * Q&A / explanation missing-metric behavior. Pair with GROUNDING_INSTRUCTION
 * when the model answers questions (Ask AthleteIQ, explainability).
 */
export const MISSING_METRIC_DISCLOSE =
  'If a metric is missing, say it is not in the data.';

/**
 * Narrative missing-metric behavior. Pair with GROUNDING_INSTRUCTION when the
 * model writes a summary and should skip absent fields (weekly report)
 * rather than narrating the gap. Intentional vs DISCLOSE: summary vs Q&A.
 */
export const MISSING_METRIC_OMIT =
  'If a metric is null or missing, do not mention it.';

/**
 * Orchestrator add-on. Grounding is tool-based by design — the agent must
 * call tools rather than reading a pasted context block.
 */
export const TOOL_GROUNDING_INSTRUCTION =
  `Ground every claim in tool results (getRiskAssessment, getPerformancePrediction, getAthleteHistory). ${GROUNDING_INSTRUCTION} Treat tool JSON as the provided data.`;

/** Knowledge Agent: don't invent literature. */
export const CORPUS_GROUNDING_INSTRUCTION =
  `Use ONLY the retrieved reference notes. Do not invent papers, authors, journals, or years. ${GROUNDING_INSTRUCTION}`;

/**
 * Risk always beats performance. Applies to the Orchestrator's single action
 * and to every graded tier (Conservative, Moderate, and Minimal change).
 */
export const RISK_OVERRIDES_PERFORMANCE_CLAUSE = `HARD SAFETY CONSTRAINT (never violate):
- Protecting the athlete comes first.
- If there is genuine ambiguity OR elevated risk (MEDIUM or HIGH), prioritize athlete safety over performance optimization. Never the reverse.
- A strong performance prediction must not override a MEDIUM or HIGH risk call. You may acknowledge that performance looks good, but the action must still reduce load or intensity.
- When risk is HIGH or MEDIUM, no action and no graded option (Conservative, Moderate, or Minimal change) may be full unrestricted training. Never "continue training as planned", "train as hard as planned", or equivalent.
- Only recommend "continue training as planned" (or equivalent) when risk is LOW and there is no serious ambiguity in the signals.`;

/** Canonical medical line for any prompt that talks about pain, injury, or training intensity. */
export const MEDICAL_DISCLAIMER =
  'This is a training/triage aid, not a medical diagnosis. Do not diagnose injury or recommend treatment. You are not a doctor.';

/** Extra for Ask AthleteIQ: what to do instead of medical advice. */
export const MEDICAL_ESCALATE =
  'For pain, injury, or medical questions, acknowledge the concern briefly and tell them to flag it with their coach or a medical professional rather than giving medical advice.';

/**
 * Double `{` / `}` so ChatPromptTemplate treats a JSON example as literal.
 * Use this for every ChatPromptTemplate system prompt that shows JSON.
 */
export function jsonExampleForChatPrompt(example: string): string {
  return example.replace(/\{/g, '{{').replace(/\}/g, '}}');
}
