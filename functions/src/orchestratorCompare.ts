/**
 * Side-by-side: tool outputs + rule baseline vs LangChain Orchestrator.
 * Run: npm run test:orchestrator
 */

import { assessRisk } from './riskModel';
import { buildRecommendation } from './recommendationEngine';
import {
  getAthleteHistory,
  getPerformancePrediction,
  getRiskAssessment,
} from './orchestratorTools';
import { runOrchestratorAgent } from './orchestratorAgent';
import { fixtureCheckInLoader, ORCHESTRATOR_FIXTURES } from './orchestratorFixtures';

async function main(): Promise<void> {
  const load = fixtureCheckInLoader();

  console.log('=== Orchestrator comparison (4 fixture athletes) ===\n');

  for (const fixture of ORCHESTRATOR_FIXTURES) {
    const assessment = assessRisk(fixture.entries, fixture.sportGroup);
    const rules = buildRecommendation(
      assessment.riskLevel,
      assessment.performancePrediction,
      fixture.sportGroup,
    );

    const risk = JSON.parse(await getRiskAssessment(fixture.id, load)) as {
      riskLevel: string;
    };
    const perf = JSON.parse(await getPerformancePrediction(fixture.id, load)) as {
      performancePrediction: string;
      performanceFrame?: string;
    };
    const hist = JSON.parse(await getAthleteHistory(fixture.id, 7, load)) as {
      checkInCount: number;
    };

    const riskMatch = risk.riskLevel === fixture.expectedRisk ? 'OK' : 'CHECK';

    const agent = await runOrchestratorAgent({
      athleteUid: fixture.id,
      sportGroup: fixture.sportGroup,
      loadEntries: load,
      persistTrace: false,
    });

    console.log(`--- ${fixture.name} [${fixture.id}] ---`);
    console.log(`  story: ${fixture.story}`);
    console.log(
      `  tools: risk=${risk.riskLevel} (${riskMatch} vs expected ${fixture.expectedRisk}), perf=${perf.performancePrediction} (${perf.performanceFrame ?? '—'}), historyDays=${hist.checkInCount}`,
    );
    console.log(`  rules: ${rules.action}`);
    console.log(`         ${rules.orchestratorNote}`);
    console.log(
      `  agent: source=${agent.source} override=${agent.safetyOverride} agreed=${agent.agreedWithRules}`,
    );
    console.log(`         ${agent.action}`);
    console.log(`         ${agent.orchestratorNote}`);
    if (agent.trace.length) {
      console.log('  trace:');
      for (const step of agent.trace) {
        if (step.type === 'tool') {
          console.log(`    ${step.order}. ${step.tool}(${JSON.stringify(step.input)})`);
        } else {
          console.log(`    ${step.order}. decision: ${step.why}`);
        }
      }
    }
    console.log('');
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
