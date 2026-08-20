import 'package:flutter/material.dart';
import '../models/athlete.dart';
import '../models/checkin.dart';
import '../models/risk_result.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/performance_tips.dart';
import '../widgets/async_body.dart';
import '../widgets/empty_state.dart';
import '../widgets/hero_card.dart';

class MyPerformanceScreen extends StatelessWidget {
  final String athleteUid;

  const MyPerformanceScreen({super.key, required this.athleteUid});

  @override
  Widget build(BuildContext context) {
    final fs = FirestoreService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My performance'),
        centerTitle: true,
      ),
      body: StreamBuilder<AthleteProfile>(
        stream: fs.athleteProfile(athleteUid),
        builder: (context, profileSnap) {
          return StreamBuilder<RiskResult?>(
            stream: fs.latestRiskResult(athleteUid),
            builder: (context, riskSnap) {
              return StreamBuilder<List<CheckIn>>(
                stream: fs.recentCheckIns(athleteUid, days: 14),
                builder: (context, checkInSnap) {
                  final blocked = asyncBodyAny(
                    [profileSnap, riskSnap, checkInSnap],
                    heading: 'Could not load performance',
                  );
                  if (blocked != null) return blocked;

                  final result = riskSnap.data;
                  if (result == null) {
                    return const Center(
                      child: EmptyState(
                        icon: Icons.track_changes,
                        heading: 'Performance not ready yet',
                        subtext:
                            'AthleteIQ needs a few days of check-ins before the Banister performance read is reliable. No tips are shown until that forecast exists.',
                      ),
                    );
                  }

                  final profile = profileSnap.data;
                  final checkIns = checkInSnap.data ?? [];
                  final perfStatus = result.performanceDisplay;
                  final axis = result.performanceAxisLabel;
                  final tips = buildPerformanceTips(
                    profile: profile,
                    result: result,
                    checkIns: checkIns,
                  );

                  return SafeArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.screenEdge),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          HeroGradientCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const IconBadge(icon: Icons.track_changes, size: 40),
                                const SizedBox(height: 14),
                                Text(
                                  axis.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.mint,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  perfStatus,
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  result.isReleasedToAthlete &&
                                          result.reason.trim().isNotEmpty
                                      ? result.reason
                                      : 'Scores come from your check-ins. Personalized guidance appears after your coach reviews the plan.',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 6,
                                  children: [
                                    _MetricChip(
                                      label: 'ACWR',
                                      value: result.acwr.toStringAsFixed(2),
                                    ),
                                    _MetricChip(
                                      label: 'Recovery',
                                      value: result.recoveryTrend,
                                    ),
                                    _MetricChip(
                                      label: '7d load',
                                      value: result.trainingLoad7d.toStringAsFixed(0),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Based on your data',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            profile != null && profile.hasSport
                                ? 'Tips use your ${profile.sportsLabel} profile, latest risk read, and recent check-ins.'
                                : 'Tips use your latest risk read and recent check-ins.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (tips.isEmpty)
                            const EmptyState(
                              icon: Icons.lightbulb_outline,
                              heading: 'No tips yet',
                              subtext:
                                  'Log sleep, fatigue, and sessions on your check-ins — AthleteIQ will surface grounded tips here instead of generic advice.',
                            )
                          else
                            for (final tip in tips) ...[
                              _TipCard(icon: tip.icon, text: tip.text),
                              const SizedBox(height: 10),
                            ],
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TipCard({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.cardSmall),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.mint, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
