import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/athlete.dart';
import '../models/checkin.dart';
import '../models/pain_report.dart';
import '../models/privacy_settings.dart';
import '../models/risk_latest.dart';
import '../models/risk_result.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/athlete_data_completeness.dart';
import '../utils/privacy_redaction.dart';
import '../utils/friendly_error.dart';
import '../widgets/async_body.dart';
import '../widgets/risk_chip.dart';
import '../widgets/stat_card.dart';
import '../widgets/why_this_call_factors.dart';
import 'coach_supporting_research_screen.dart';
import 'coach_trends_screen.dart';
import 'injury_risk_screen.dart';
import 'not_enough_data_screen.dart';
import 'orchestrator_conflict_screen.dart';
import 'performance_forecast_screen.dart';
import 'weekly_report_screen.dart';

class CoachDashboardScreen extends StatelessWidget {
  final AthleteProfile athlete;
  const CoachDashboardScreen({super.key, required this.athlete});

  @override
  Widget build(BuildContext context) {
    final fs = FirestoreService();

    return StreamBuilder<AthleteProfile>(
      stream: fs.athleteProfile(athlete.uid),
      builder: (context, profileSnap) {
        final profile = profileSnap.data ?? athlete;
        return Scaffold(
          appBar: AppBar(title: Text(profile.name)),
          body: StreamBuilder<RiskLatest>(
            stream: fs.streamRiskLatest(profile.uid),
            builder: (context, snapshot) {
              final blocked = asyncBodyAny(
                [profileSnap, snapshot],
                heading: 'Could not load this athlete',
              );
              if (blocked != null) {
                return blocked;
              }

              final latest = snapshot.data;
              final result = latest?.result;
              final isPending = result != null &&
                  (result.recommendationStatus ?? 'pending') == 'pending';
              final privacy = profile.privacySettings;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.screenEdge),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DataCompletenessBanner(athlete: profile),
                    if (!privacy.allShared) ...[
                      const SizedBox(height: 12),
                      _PrivacyWithheldBanner(privacy: privacy),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    PerformanceForecastScreen(athlete: profile),
                              ),
                            ),
                            icon: const Icon(Icons.track_changes, size: 18),
                            label: const Text('Forecast'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => InjuryRiskScreen(athlete: profile),
                              ),
                            ),
                            icon: const Icon(Icons.analytics_outlined, size: 18),
                            label: const Text('Risk detail'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _PainReportsSection(
                      athleteUid: profile.uid,
                      privacy: privacy,
                    ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => WeeklyReportScreen(
                              athleteUid: profile.uid,
                              athleteName: profile.name,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.calendar_view_week, size: 18),
                        label: const Text('Week in review'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final coachUid =
                              profile.coachUid ?? FirebaseAuth.instance.currentUser?.uid;
                          if (coachUid == null) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CoachTrendsScreen(
                                coachUid: coachUid,
                                initialAthleteUid: profile.uid,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.show_chart_outlined, size: 18),
                        label: const Text('Trends'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    final coachUid =
                        profile.coachUid ?? FirebaseAuth.instance.currentUser?.uid;
                    if (coachUid == null) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CoachSupportingResearchScreen(
                          coachUid: coachUid,
                          athlete: profile,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('Supporting research'),
                ),
                const SizedBox(height: 16),
                if (result == null)
                  StreamBuilder<List<CheckIn>>(
                    stream: fs.recentCheckIns(profile.uid, days: 35),
                    builder: (context, checkSnap) {
                      final checkBlocked = asyncBody(
                        checkSnap,
                        heading: 'Could not load check-ins',
                      );
                      if (checkBlocked != null) return checkBlocked;

                      final fromDoc = latest?.insufficientData == true
                          ? latest!.checkInCount
                          : null;
                      final count = fromDoc ?? (checkSnap.data?.length ?? 0);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: NotEnoughDataScreen(
                          checkInCount: count,
                          joinedAt: profile.createdAt,
                        ),
                      );
                    },
                  )
                else ...[
                Row(
                  children: [
                    RiskChip(level: result.riskLevel),
                    const SizedBox(width: 8),
                    Text(
                      'Confidence: ${sharedOrHidden(privacy.wearableData, result.confidence)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: 'ACWR',
                        value: sharedOrHidden(
                          privacy.trainingLogs,
                          result.acwr.toStringAsFixed(2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatCard(
                        label: '7d load',
                        value: sharedOrHidden(
                          privacy.trainingLogs,
                          result.trainingLoad7d.toStringAsFixed(0),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatCard(
                        label: '28d avg',
                        value: sharedOrHidden(
                          privacy.trainingLogs,
                          result.trainingLoad28dAvg.toStringAsFixed(0),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: 'Recovery trend',
                        value: sharedOrHidden(
                          privacy.wearableData,
                          result.recoveryTrend,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatCard(
                        label: result.performanceAxisLabel,
                        value: sharedOrHidden(
                          privacy.trainingLogs,
                          result.performanceDisplay,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                WhyThisCallFactors(result: result, privacy: privacy),
                if (result.orchestratorConflict?.present == true) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OrchestratorConflictScreen(
                          athlete: profile,
                          result: result,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.balance, size: 18),
                    label: const Text('Risk vs performance conflict'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.amber,
                      side: BorderSide(color: AppColors.amber.withValues(alpha: 0.5)),
                    ),
                  ),
                ],
                if (result.performanceReasoningLLM != null &&
                    result.performanceReasoningLLM!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'PERFORMANCE READ',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    result.performanceReasoningLLM!,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ],
                if (result.researchCitations.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('SUPPORTING RESEARCH',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.mint,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6)),
                  const SizedBox(height: 8),
                  ...result.researchCitations.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ResearchCiteCard(citation: c),
                    ),
                  ),
                  if (result.researchNote != null &&
                      result.researchNote!.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(
                              color: AppColors.amber, width: 2),
                        ),
                      ),
                      child: Text(
                        result.researchNote!,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('RECOMMENDATION',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.coral, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(result.recommendation, style: const TextStyle(fontSize: 15)),
                      if (result.recommendationStatus != null && !isPending) ...[
                        const SizedBox(height: 8),
                        Text('Status: ${result.recommendationStatus}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
                if (result.gradedOptions.isNotEmpty && isPending) ...[
                  const SizedBox(height: 16),
                  Text(
                    'GRADED OPTIONS',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < result.gradedOptions.length; i++)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: i < result.gradedOptions.length - 1 ? 8 : 0,
                              ),
                              child: _GradedOptionCard(
                                option: result.gradedOptions[i],
                                onApprove: () async {
                                  final option = result.gradedOptions[i];
                                  try {
                                    await fs.reviewRecommendation(
                                      profile.uid,
                                      decision: 'approved',
                                      modifiedText: option.action,
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Approved ${option.tier} option for ${profile.name}',
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(friendlyError(e))),
                                      );
                                    }
                                  }
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (isPending) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            try {
                              await fs.reviewRecommendation(profile.uid, decision: 'approved');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Primary recommendation approved'),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(friendlyError(e))),
                                );
                              }
                            }
                          },
                          child: const Text('Approve primary'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            try {
                              await fs.reviewRecommendation(profile.uid, decision: 'rejected');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Recommendation rejected')),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(friendlyError(e))),
                                );
                              }
                            }
                          },
                          child: const Text('Reject'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => _showModifyDialog(context, fs, profile.uid, result),
                    child: const Text('Modify before sending'),
                  ),
                ],
                ],
              ],
            ),
          );
            },
          ),
        );
      },
    );
  }

  void _showModifyDialog(
    BuildContext context,
    FirestoreService fs,
    String athleteUid,
    RiskResult result,
  ) {
    final controller = TextEditingController(text: result.recommendation);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Modify recommendation'),
        content: TextField(controller: controller, maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              try {
                await fs.reviewRecommendation(
                  athleteUid,
                  decision: 'modified',
                  modifiedText: controller.text,
                );
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(friendlyError(e))),
                  );
                }
              }
            },
            child: const Text('Send to athlete'),
          ),
        ],
      ),
    );
  }
}

class _DataCompletenessBanner extends StatelessWidget {
  final AthleteProfile athlete;

  const _DataCompletenessBanner({required this.athlete});

  @override
  Widget build(BuildContext context) {
    final fs = FirestoreService();

    return StreamBuilder(
      stream: fs.recentCheckIns(athlete.uid, days: 14),
      builder: (context, snapshot) {
        final checkIns = snapshot.data ?? [];
        if (snapshot.hasError) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'Could not load data completeness: ${friendlyError(snapshot.error)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.coral,
                height: 1.35,
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const SizedBox(
            height: 48,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.mint,
                ),
              ),
            ),
          );
        }

        final info = AthleteDataCompleteness.analyze(athlete, checkIns);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: info.hasGaps ? AppColors.riskMedBg : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: info.hasGaps
                  ? AppColors.amber.withValues(alpha: 0.4)
                  : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    info.hasGaps ? Icons.info_outline : Icons.check_circle_outline,
                    size: 16,
                    color: info.hasGaps ? AppColors.amber : AppColors.mint,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      info.tierLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: info.hasGaps ? AppColors.amber : AppColors.mint,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                info.tierSummary,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
              if (info.missing.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final gap in info.missing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $gap',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PrivacyWithheldBanner extends StatelessWidget {
  final PrivacySettings privacy;
  const _PrivacyWithheldBanner({required this.privacy});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SHARING LIMITS',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This athlete is not sharing: ${privacy.withheldLabels.join('; ')}.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _PainReportsSection extends StatelessWidget {
  final String athleteUid;
  final PrivacySettings privacy;
  const _PainReportsSection({required this.athleteUid, required this.privacy});

  @override
  Widget build(BuildContext context) {
    if (!privacy.injuryHistory) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PAIN REPORTS',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This athlete is not sharing injury history.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    final fs = FirestoreService();
    return StreamBuilder<List<PainReport>>(
      stream: fs.streamPainReports(athleteUid),
      builder: (context, snapshot) {
        final loading =
            snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData;
        final reports = snapshot.data ?? [];
        PainReport? latestHigh;
        for (final report in reports) {
          if (report.isHigh) {
            latestHigh = report;
            break;
          }
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'PAIN REPORTS',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  if (reports.isNotEmpty) ...[
                    const Spacer(),
                    Text(
                      '${reports.length} report${reports.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Read-only history from athlete submissions.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
              if (loading) ...[
                const SizedBox(height: 16),
                const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.mint,
                    ),
                  ),
                ),
              ] else if (snapshot.hasError) ...[
                const SizedBox(height: 12),
                Text(
                  'Could not load pain reports. ${friendlyError(snapshot.error)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.coral,
                    height: 1.35,
                  ),
                ),
              ] else if (reports.isEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'No pain reports yet. When this athlete submits a report from '
                  'Report pain in their app, it will appear here.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    height: 1.45,
                  ),
                ),
              ] else ...[
                if (latestHigh != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.riskHighBg,
                      border: Border.all(color: AppColors.coral.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'HIGH PAIN TRIAGE',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.coral,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          latestHigh.urgencyReason ??
                              'Latest report was flagged HIGH for coach review.',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Triage aid only — not a diagnosis. Ask the athlete and, if needed, a medical professional.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                for (final report in reports) _PainReportCard(report: report),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PainReportCard extends StatelessWidget {
  final PainReport report;
  const _PainReportCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final urgency = (report.urgency ?? '—').toUpperCase();
    final color = AppColors.forRisk(urgency == '—' ? 'LOW' : urgency);
    final areas = report.areas
        .map((a) => '${a.location} (${a.severity}/5)')
        .join(', ');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: report.isHigh
              ? AppColors.coral.withValues(alpha: 0.45)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                urgency,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              Text(
                '${report.date.year}-${report.date.month.toString().padLeft(2, '0')}-${report.date.day.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            areas,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (report.note != null && report.note!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              report.note!,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
          if (report.urgencyReason != null && report.urgencyReason!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              report.urgencyReason!,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GradedOptionCard extends StatelessWidget {
  final GradedOption option;
  final VoidCallback onApprove;

  const _GradedOptionCard({
    required this.option,
    required this.onApprove,
  });

  Color _tierColor() {
    switch (option.tier) {
      case 'Conservative':
        return AppColors.coral;
      case 'Moderate':
        return AppColors.amber;
      default:
        return AppColors.mint;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tierColor = _tierColor();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            option.tier.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: tierColor,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            option.action,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textPrimary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            option.reason,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              height: 1.3,
            ),
          ),
          const Spacer(),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: onApprove,
            style: OutlinedButton.styleFrom(
              foregroundColor: tierColor,
              side: BorderSide(color: tierColor.withValues(alpha: 0.6)),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
            child: const Text('Approve this', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

class _ResearchCiteCard extends StatelessWidget {
  final ResearchCitation citation;
  const _ResearchCiteCard({required this.citation});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            citation.tag.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.mint,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            citation.text,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            citation.source,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
