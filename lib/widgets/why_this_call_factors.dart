import 'package:flutter/material.dart';
import '../models/privacy_settings.dart';
import '../models/risk_result.dart';
import '../theme/app_theme.dart';

/// Factor cards for Why this call. Thresholds match `riskModel.ts`
/// (1.5 danger, 1.3 climb, 0.8–1.3 sweet spot; persistent fatigue = 4 days ≥ 4).
class WhyThisCallFactors extends StatelessWidget {
  final RiskResult result;
  final PrivacySettings? privacy;

  const WhyThisCallFactors({super.key, required this.result, this.privacy});

  @override
  Widget build(BuildContext context) {
    final share = privacy ?? PrivacySettings.open;
    final acwr = share.trainingLogs
        ? _acwrFactor(result.acwr)
        : _withheldFactor('ACWR', 'Training logs are not shared with you.');
    final recovery = share.wearableData
        ? _recoveryFactor(result.recoveryTrend)
        : _withheldFactor(
            'Recovery trend',
            'Wearable data (HRV, sleep, resting HR) is not shared with you.',
          );
    final fatigue = share.dailyFatigueCheckIn
        ? _fatigueFactor(
            persistent: result.fatiguePersistent,
            avg: result.avgFatigue7d,
          )
        : _withheldFactor(
            'Fatigue',
            'Daily fatigue check-ins are not shared with you.',
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'WHY THIS CALL',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 10),
        _FactorCard(factor: acwr),
        const SizedBox(height: 8),
        _FactorCard(factor: recovery),
        const SizedBox(height: 8),
        _FactorCard(factor: fatigue),
        if (result.riskLevelPatternFlag != null &&
            result.riskLevelPatternFlag!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: AppColors.amber, width: 2),
              ),
            ),
            child: Text(
              result.riskLevelPatternFlag!,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Factor {
  final String title;
  final String value;
  final String detail;
  final bool elevatesRisk;
  final String badge;

  const _Factor({
    required this.title,
    required this.value,
    required this.detail,
    required this.elevatesRisk,
    required this.badge,
  });
}

_Factor _withheldFactor(String title, String detail) {
  return _Factor(
    title: title,
    value: PrivacySettings.notShared,
    detail: detail,
    elevatesRisk: false,
    badge: 'Hidden',
  );
}

_Factor _acwrFactor(double acwr) {
  if (acwr > 1.5) {
    return _Factor(
      title: 'ACWR',
      value: acwr.toStringAsFixed(2),
      detail: 'Above the 1.5 danger line — load spiked vs the 28-day baseline.',
      elevatesRisk: true,
      badge: 'Elevates risk',
    );
  }
  if (acwr > 1.3) {
    return _Factor(
      title: 'ACWR',
      value: acwr.toStringAsFixed(2),
      detail: 'Climbing (above 1.3). Not yet in the danger zone, but load is rising.',
      elevatesRisk: true,
      badge: 'Elevates risk',
    );
  }
  if (acwr >= 0.8) {
    return _Factor(
      title: 'ACWR',
      value: acwr.toStringAsFixed(2),
      detail: 'Inside the 0.8–1.3 sweet-spot band.',
      elevatesRisk: false,
      badge: 'Stable',
    );
  }
  return _Factor(
    title: 'ACWR',
    value: acwr.toStringAsFixed(2),
    detail: 'Below 0.8 — acute load is light vs chronic. Not an elevated-risk driver.',
    elevatesRisk: false,
    badge: 'Low load',
  );
}

_Factor _recoveryFactor(String trend) {
  switch (trend) {
    case 'worsening':
      return const _Factor(
        title: 'Recovery trend',
        value: 'Worsening',
        detail: 'HRV / sleep / RHR / fatigue votes point down vs the prior week.',
        elevatesRisk: true,
        badge: 'Elevates risk',
      );
    case 'improving':
      return const _Factor(
        title: 'Recovery trend',
        value: 'Improving',
        detail: 'Recovery signals look better than the prior week.',
        elevatesRisk: false,
        badge: 'Supportive',
      );
    default:
      return const _Factor(
        title: 'Recovery trend',
        value: 'Stable',
        detail: 'No clear week-to-week shift in recovery.',
        elevatesRisk: false,
        badge: 'Stable',
      );
  }
}

_Factor _fatigueFactor({required bool persistent, double? avg}) {
  final avgText = avg == null ? '' : ' 7-day average ${avg.toStringAsFixed(1)}/5.';
  if (persistent) {
    return _Factor(
      title: 'Fatigue',
      value: 'Stuck high',
      detail: 'Fatigue ≥ 4 for four days running.$avgText',
      elevatesRisk: true,
      badge: 'Elevates risk',
    );
  }
  return _Factor(
    title: 'Fatigue',
    value: avg == null ? 'Clearing' : avg.toStringAsFixed(1),
    detail: 'Not a persistent high-fatigue streak.$avgText',
    elevatesRisk: false,
    badge: 'Not a driver',
  );
}

class _FactorCard extends StatelessWidget {
  final _Factor factor;

  const _FactorCard({required this.factor});

  @override
  Widget build(BuildContext context) {
    final color = factor.elevatesRisk ? AppColors.coral : AppColors.mint;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: factor.elevatesRisk
              ? AppColors.coral.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  factor.title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  factor.value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  factor.detail,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(
              factor.badge.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
