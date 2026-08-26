import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/athlete.dart';
import '../models/checkin.dart';
import '../models/privacy_settings.dart';
import '../models/risk_result.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/privacy_redaction.dart';
import '../utils/risk_signals.dart';
import '../widgets/async_body.dart';
import '../widgets/hero_card.dart';
import '../widgets/responsive_chart_frame.dart';
import 'not_enough_data_screen.dart';

/// Coach performance forecast — Banister band over time plus current drivers.
class PerformanceForecastScreen extends StatelessWidget {
  final AthleteProfile athlete;

  const PerformanceForecastScreen({super.key, required this.athlete});

  @override
  Widget build(BuildContext context) {
    final fs = FirestoreService();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Forecast · ${athlete.name}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<RiskResult?>(
        stream: fs.latestRiskResult(athlete.uid),
        builder: (context, latestSnap) {
          return StreamBuilder<List<RiskHistoryPoint>>(
            stream: fs.streamRiskHistory(athlete.uid),
            builder: (context, historySnap) {
              return StreamBuilder<List<CheckIn>>(
                stream: fs.recentCheckIns(athlete.uid, days: 35),
                builder: (context, checkInSnap) {
                  final blocked = asyncBodyAny(
                    [latestSnap, historySnap, checkInSnap],
                    heading: 'Could not load this forecast',
                  );
                  if (blocked != null) return blocked;

                  final latest = latestSnap.data;
                  final stored = historySnap.data ?? [];
                  final checkIns = checkInSnap.data ?? [];
                  final series = _forecastSeries(stored, checkIns, latest);

                  if (latest == null && series.isEmpty) {
                    return NotEnoughDataScreen(
                      checkInCount: checkIns.length,
                      joinedAt: athlete.createdAt,
                    );
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.screenEdge),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CurrentBandCard(
                          latest: latest,
                          privacy: athlete.privacySettings,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'PERFORMANCE TREND',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Same Banister Fitness–Fatigue read every day (GOOD / AVERAGE / DECLINING). '
                          'Phrasing follows this athlete\'s sport group — not a separate model.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (!athlete.privacySettings.trainingLogs)
                          Text(
                            'Training logs are not shared with you, so the performance trend is hidden.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          )
                        else if (series.length < 2)
                          Text(
                            'Not enough history for a trend yet. The line fills in as nightly '
                            'recalculations write dated riskResults snapshots.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          )
                        else
                          _PerformanceLineChart(points: series),
                        const SizedBox(height: 24),
                        Text(
                          'DRIVERS OF THIS READ',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _DriversSection(
                          latest: latest,
                          checkIns: checkIns,
                          lastPoint: series.isEmpty ? null : series.last,
                          privacy: athlete.privacySettings,
                        ),
                      ],
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

List<RiskHistoryPoint> _forecastSeries(
  List<RiskHistoryPoint> stored,
  List<CheckIn> checkIns,
  RiskResult? latest,
) {
  var points = stored.length >= 2 ? List<RiskHistoryPoint>.from(stored) : reconstructRiskHistory(checkIns);
  if (latest != null) {
    final fromLatest = RiskHistoryPoint.fromLatest(latest);
    final exists = points.any(
      (p) =>
          p.id == fromLatest.id ||
          _sameDay(p.date, fromLatest.date),
    );
    if (!exists) points.add(fromLatest);
  }
  points.sort((a, b) => a.date.compareTo(b.date));
  return points;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _CurrentBandCard extends StatelessWidget {
  final RiskResult? latest;
  final PrivacySettings privacy;

  const _CurrentBandCard({required this.latest, required this.privacy});

  @override
  Widget build(BuildContext context) {
    final label = privacy.trainingLogs
        ? (latest?.performanceDisplay ?? 'Not scored')
        : kPrivacyNotShared;
    final axis = latest?.performanceAxisLabel ?? 'Performance';

    return HeroGradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            axis.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.mint,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          if (latest != null) ...[
            const SizedBox(height: 8),
            Text(
              'Canonical band: ${latest!.performancePrediction}',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PerformanceLineChart extends StatelessWidget {
  final List<RiskHistoryPoint> points;

  const _PerformanceLineChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].performanceY),
    ];
    final dateFmt = DateFormat('M/d');

    return ResponsiveChartFrame(
      maxHeight: 240,
      minHeight: 150,
      builder: (context, size) {
        final reservedLeft = size.width < 360 ? 52.0 : 78.0;
        return LineChart(
        LineChartData(
          minY: -0.2,
          maxY: 2.2,
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (v) => FlLine(
              color: AppColors.border.withValues(alpha: 0.7),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: reservedLeft,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final label = switch (value.round()) {
                    2 => 'GOOD',
                    1 => 'AVERAGE',
                    0 => 'DECLINING',
                    _ => '',
                  };
                  if (label.isEmpty) return const SizedBox.shrink();
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                    label,
                    style: TextStyle(fontSize: 9, color: AppColors.textMuted),
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: (points.length / 4).clamp(1, 7).toDouble(),
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  if (i != 0 && i != points.length - 1 && i % ((points.length / 4).ceil()) != 0) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    dateFmt.format(points[i].date),
                    style: TextStyle(fontSize: 9, color: AppColors.textMuted),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.surfaceAlt,
              getTooltipItems: (touched) => touched.map((s) {
                final p = points[s.x.round().clamp(0, points.length - 1)];
                return LineTooltipItem(
                  '${dateFmt.format(p.date)}\n${p.performanceFrame ?? p.performancePrediction}',
                  TextStyle(color: AppColors.textPrimary, fontSize: 12),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppColors.mint,
              barWidth: 2.5,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.mint.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
        duration: Duration.zero,
      );
      },
    );
  }
}

class _DriversSection extends StatelessWidget {
  final RiskResult? latest;
  final List<CheckIn> checkIns;
  final RiskHistoryPoint? lastPoint;
  final PrivacySettings privacy;

  const _DriversSection({
    required this.latest,
    required this.checkIns,
    required this.lastPoint,
    required this.privacy,
  });

  @override
  Widget build(BuildContext context) {
    final last4 = checkIns.take(4).toList();
    final fatiguePersistent = privacy.dailyFatigueCheckIn &&
        last4.length == 4 &&
        last4.every((c) => c.fatigueScore >= 4);
    final avgFatigue = !privacy.dailyFatigueCheckIn || checkIns.isEmpty
        ? null
        : checkIns.take(7).fold<double>(0, (s, c) => s + c.fatigueScore) /
            checkIns.take(7).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DriverRow(
          label: 'Recovery trend',
          value: sharedOrHidden(
            privacy.wearableData,
            latest?.recoveryTrend ?? lastPoint?.recoveryTrend ?? '—',
          ),
        ),
        _DriverRow(
          label: '7-day load',
          value: sharedOrHidden(
            privacy.trainingLogs,
            latest != null
                ? latest!.trainingLoad7d.toStringAsFixed(0)
                : lastPoint?.trainingLoad7d.toStringAsFixed(0) ?? '—',
          ),
        ),
        _DriverRow(
          label: '28-day weekly avg',
          value: sharedOrHidden(
            privacy.trainingLogs,
            latest != null
                ? latest!.trainingLoad28dAvg.toStringAsFixed(0)
                : lastPoint?.trainingLoad28dAvg.toStringAsFixed(0) ?? '—',
          ),
        ),
        _DriverRow(
          label: '7-day avg fatigue',
          value: privacy.dailyFatigueCheckIn
              ? (avgFatigue == null ? '—' : avgFatigue.toStringAsFixed(1))
              : kPrivacyNotShared,
        ),
        _DriverRow(
          label: 'Persistent fatigue (4d ≥ 4)',
          value: privacy.dailyFatigueCheckIn
              ? (fatiguePersistent ? 'Yes' : 'No')
              : kPrivacyNotShared,
        ),
        if (latest?.performanceReasoningLLM != null &&
            latest!.performanceReasoningLLM!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WHY THIS READ',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  latest!.performanceReasoningLLM!,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DriverRow extends StatelessWidget {
  final String label;
  final String value;

  const _DriverRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
