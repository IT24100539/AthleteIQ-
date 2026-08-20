import 'package:flutter/material.dart';
import '../models/athlete.dart';
import '../models/risk_result.dart';
import '../theme/app_theme.dart';
import '../widgets/risk_chip.dart';

/// Shown when `buildRecommendation()` stored `orchestratorConflict.present`.
/// Winner / why come from that object — not re-derived here.
class OrchestratorConflictScreen extends StatelessWidget {
  final AthleteProfile athlete;
  final RiskResult result;

  const OrchestratorConflictScreen({
    super.key,
    required this.athlete,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final conflict = result.orchestratorConflict;
    if (conflict == null || !conflict.present) {
      return Scaffold(
        appBar: AppBar(title: const Text('Orchestrator')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No risk vs performance conflict on file for this athlete.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
        ),
      );
    }

    final riskWon = conflict.winner == 'risk';
    final actionWon = conflict.actionWon ?? result.recommendation;
    final rulesAction = conflict.ruleBasedAction ?? result.ruleBasedRecommendation;

    return Scaffold(
      appBar: AppBar(
        title: Text('Conflict · ${athlete.name}'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenEdge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.riskMedBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.amber.withValues(alpha: 0.45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'RISK AND PERFORMANCE DISAGREE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.amber,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    conflict.why,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _SideCard(
                    title: 'Risk',
                    won: riskWon,
                    child: RiskChip(level: conflict.riskLevel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SideCard(
                    title: 'Performance',
                    won: conflict.winner == 'performance',
                    child: Text(
                      conflict.performancePrediction,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.mint.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WHAT WON · ${conflict.winnerLabel.toUpperCase()}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.mint,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _winnerPlainLanguage(conflict),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    actionWon,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (conflict.safetyOverride) ...[
              const SizedBox(height: 12),
              const Text(
                'The agent briefly proposed a full-training plan. A safety override '
                'replaced it with the rule-based action — elevated risk cannot lose '
                'to performance.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.coral,
                  height: 1.4,
                ),
              ),
            ],
            if (rulesAction != null &&
                rulesAction.isNotEmpty &&
                rulesAction != actionWon) ...[
              const SizedBox(height: 16),
              Text(
                'RULE-BASED BASELINE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                rulesAction,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'This call comes from buildRecommendation() in the Orchestrator '
              '(Section 15.2): risk outranks performance when they disagree. '
              'Source: ${conflict.source ?? result.orchestratorSource ?? 'rules'}.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _winnerPlainLanguage(OrchestratorConflict conflict) {
    switch (conflict.kind) {
      case 'elevated_risk_vs_strong_performance':
        return 'Risk won. The performance read is GOOD, but ${conflict.riskLevel} '
            'risk still sets the plan — protecting the athlete comes first.';
      case 'low_risk_vs_declining_performance':
        return 'Performance broke the tie. Risk is LOW, so the declining performance '
            'read is allowed to suggest a light deload rather than full training as planned.';
      default:
        return conflict.why;
    }
  }
}

class _SideCard extends StatelessWidget {
  final String title;
  final bool won;
  final Widget child;

  const _SideCard({
    required this.title,
    required this.won,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: won ? AppColors.mint.withValues(alpha: 0.08) : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: won ? AppColors.mint.withValues(alpha: 0.5) : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.6,
                ),
              ),
              if (won) ...[
                const Spacer(),
                const Text(
                  'WON',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.mint,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
