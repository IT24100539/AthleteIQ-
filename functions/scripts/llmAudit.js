/**
 * Evidence audit for Phases E2–E5. Loads functions/.env the same way the
 * emulator would. Never prints secret values.
 */
const fs = require('fs');
const path = require('path');

function loadDotEnv() {
  const envPath = path.join(__dirname, '..', '.env');
  if (!fs.existsSync(envPath)) return { loaded: false };
  const raw = fs.readFileSync(envPath, 'utf8');
  for (const line of raw.split(/\r?\n/)) {
    if (!line || line.trim().startsWith('#')) continue;
    const i = line.indexOf('=');
    if (i < 1) continue;
    const k = line.slice(0, i).trim();
    const v = line.slice(i + 1).trim();
    if (process.env[k] === undefined) process.env[k] = v;
  }
  return { loaded: true };
}

loadDotEnv();

const { generateAnswer, fallbackAnswer } = require('../lib/aiChat');
const {
  generateResearchNote,
  retrieveResearchChunks,
} = require('../lib/knowledgeAgent');
const { runOrchestratorAgent } = require('../lib/orchestratorAgent');
const { generateGradedOptions, fallbackGradedOptions } = require('../lib/gradedRecommendations');
const { enrichAssessmentExplanation } = require('../lib/explainabilityLlm');
const { assessRisk } = require('../lib/riskModel');
const { fixtureCheckInLoader, ORCHESTRATOR_FIXTURES } = require('../lib/orchestratorFixtures');

function fixture(id) {
  return ORCHESTRATOR_FIXTURES.find((f) => f.id === id);
}

async function main() {
  const key = (process.env.ANTHROPIC_API_KEY || '').trim();
  console.log(
    JSON.stringify(
      {
        env: {
          keyNonEmpty: key.length > 0,
          keyLength: key.length,
          model: process.env.ANTHROPIC_MODEL || null,
        },
      },
      null,
      2,
    ),
  );

  const maya = fixture('fixture-maya-spike');
  const arthur = fixture('fixture-arthur-climb');
  const mayaRisk = assessRisk(maya.entries, maya.sportGroup);
  const arthurRisk = assessRisk(arthur.entries, arthur.sportGroup);

  const question = 'Why am I so tired this week?';
  const chat = await generateAnswer(
    question,
    maya.entries.slice(0, 14),
    mayaRisk,
    'Running',
    'Maya',
  );
  const expectedFallback = fallbackAnswer(question);

  const chunks = await retrieveResearchChunks(mayaRisk, 3);
  const research = await generateResearchNote(mayaRisk);

  const load = fixtureCheckInLoader();
  const orch = await runOrchestratorAgent({
    athleteUid: arthur.id,
    sportGroup: arthur.sportGroup,
    loadEntries: load,
    persistTrace: false,
  });

  const graded = await generateGradedOptions({
    assessment: mayaRisk,
    sportGroup: maya.sportGroup,
    sport: 'Running',
    primaryAction: 'Easy recovery session only, no intervals or race-pace work this week.',
    primaryNote: 'HIGH risk — reduce load.',
  });
  const gradedFallback = fallbackGradedOptions(
    mayaRisk,
    maya.sportGroup,
    'Easy recovery session only, no intervals or race-pace work this week.',
  );

  const explained = await enrichAssessmentExplanation(mayaRisk, maya.entries);

  console.log(
    JSON.stringify(
      {
        mayaRisk: {
          riskLevel: mayaRisk.riskLevel,
          acwr: mayaRisk.acwr,
          reason: mayaRisk.reason,
          performancePrediction: mayaRisk.performancePrediction,
        },
        arthurRisk: {
          riskLevel: arthurRisk.riskLevel,
          acwr: arthurRisk.acwr,
          reason: arthurRisk.reason,
          performancePrediction: arthurRisk.performancePrediction,
          performanceFrame: arthurRisk.performanceFrame,
        },
        askAthleteIQ: {
          question,
          source: chat.source,
          text: chat.text,
          matchesFallbackAnswer: chat.text === expectedFallback,
          expectedFallback,
        },
        knowledge: {
          source: research.source,
          note: research.note,
          citations: research.citations,
          retrievedFiles: chunks.map((d) => ({
            file: d.metadata.file,
            tag: d.metadata.tag,
            source: d.metadata.source,
            excerpt: String(d.pageContent).slice(0, 180),
          })),
          noteEqualsDefaultHighAcwr:
            research.note.includes('ACWR is a useful spike signal') &&
            research.note.includes('1.5 danger cutoff is contested'),
        },
        orchestrator: {
          athlete: arthur.name,
          source: orch.source,
          action: orch.action,
          orchestratorNote: orch.orchestratorNote,
          safetyOverride: orch.safetyOverride,
          agreedWithRules: orch.agreedWithRules,
          ruleBasedAction: orch.ruleBased.action,
          trace: orch.trace,
        },
        graded: {
          source: graded.source,
          options: graded.options,
          matchesFallbackTemplates: JSON.stringify(graded.options) === JSON.stringify(gradedFallback),
        },
        explain: {
          source: explained.source,
          riskLevelReasoningLLM: explained.riskLevelReasoningLLM,
          performanceReasoningLLM: explained.performanceReasoningLLM,
          riskLevelPatternFlag: explained.riskLevelPatternFlag,
          copiesRuleReason: explained.riskLevelReasoningLLM === mayaRisk.reason,
          ruleReason: mayaRisk.reason,
        },
      },
      null,
      2,
    ),
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
