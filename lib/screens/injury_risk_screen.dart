import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/athlete.dart';
import '../models/checkin.dart';
import '../models/risk_result.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/privacy_redaction.dart';
import '../utils/risk_signals.dart';
import '../widgets/async_body.dart';
import '../widgets/responsive_chart_frame.dart';
import '../widgets/risk_chip.dart';
import '../widgets/stat_card.dart';
import 'not_enough_data_screen.dart';

/// Coach injury-risk view — ACWR over time with 0.8–1.3 / 1.5 bands.
class InjuryRiskScreen extends StatelessWidget {
  final AthleteProfile athlete;

  const InjuryRiskScreen({super.key, required this.athlete});

  @override
  Widget build(BuildContext context) {
    final fs = FirestoreService();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Risk detail · ${athlete.name}',
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
                    heading: 'Could not load risk detail',
                  );
                  if (blocked != null) return blocked;

                  final latest = latestSnap.data;
                  final stored = historySnap.data ?? [];
                  final checkIns = checkInSnap.data ?? [];
                  final series = _riskSeries(stored, checkIns, latest);

                  if (latest == null && series.isEmpty) {
                    return NotEnoughDataScreen(
                      checkInCount: checkIns.length,
                      joinedAt: athlete.createdAt,
                    );
                  }

                  final privacy = athlete.privacySettings;
                  final acwr = latest?.acwr ?? (series.isEmpty ? 0 : series.last.acwr);
                  final recovery =
                      latest?.recoveryTrend ?? (series.isEmpty ? 'stable' : series.last.recoveryTrend);
                  final last4 = checkIns.take(4).toList();
                  final fatiguePersistent = privacy.dailyFatigueCheckIn &&
                      last4.length == 4 &&
                      last4.every((c) => c.fatigueScore >= 4);

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.screenEdge),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            if (latest != null) RiskChip(level: latest.riskLevel),
                            if (latest != null) const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                latest?.confidence ?? 'ACWR from check-in history',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
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
                                  acwr.toStringAsFixed(2),
                                ),
                                valueColor: !privacy.trainingLogs
                                    ? null
                                    : acwr > 1.5
                                        ? AppColors.coral
                                        : acwr > 1.3
                                            ? AppColors.amber
                                            : AppColors.mint,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: StatCard(
                                label: 'Recovery',
                                value: sharedOrHidden(privacy.wearableData, recovery),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: StatCard(
                                label: 'Fatigue',
                                value: privacy.dailyFatigueCheckIn
                                    ? (fatiguePersistent ? 'Stuck high' : 'Clearing')
                                    : kPrivacyNotShared,
                                valueColor: privacy.dailyFatigueCheckIn &&
                                        fatiguePersistent
                                    ? AppColors.coral
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'ACWR OVER TIME',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const _BandLegend(),
                        const SizedBox(height: 12),
                        if (!privacy.trainingLogs)
                          Text(
                            'Training logs are not shared with you, so ACWR history is hidden.',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                          )
                        else if (series.length < 2)
                          Text(
                            'Not enough history for a trend yet. Dated riskResults '
                            'snapshots fill this chart after each recalculation.',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                          )
                        else
                          _AcwrLineChart(points: series),
                        const SizedBox(height: 8),
                        Text(
                          '0.8–1.3 is the Gabbett sweet-spot band; >1.5 is the danger '
                          'line. Those cutoffs are fixed research constants (Section 18.4), '
                          'and the 1.5 figure is contested in later literature (Section 18.2) — '
                          'treat it as a flag for conversation, not a diagnosis.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'FATIGUE (1–5)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (!privacy.dailyFatigueCheckIn)
                          Text(
                            'Daily fatigue check-ins are not shared with you.',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                          )
                        else if (checkIns.length < 2)
                          Text(
                            'Log more check-ins to see daily fatigue next to ACWR.',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                          )
                        else
                          _FatigueLineChart(checkIns: checkIns),
                        if (latest != null) ...[
                          const SizedBox(height: 24),
                          _WhyCard(result: latest),
                        ],
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

List<RiskHistoryPoint> _riskSeries(
  List<RiskHistoryPoint> stored,
  List<CheckIn> checkIns,
  RiskResult? latest,
) {
  var points =
      stored.length >= 2 ? List<RiskHistoryPoint>.from(stored) : reconstructRiskHistory(checkIns);
  if (latest != null) {
    final fromLatest = RiskHistoryPoint.fromLatest(latest);
    final exists = points.any(
      (p) =>
          p.id == fromLatest.id ||
          (p.date.year == fromLatest.date.year &&
              p.date.month == fromLatest.date.month &&
              p.date.day == fromLatest.date.day),
    );
    if (!exists) points.add(fromLatest);
  }
  points.sort((a, b) => a.date.compareTo(b.date));
  return points;
}

class _BandLegend extends StatelessWidget {
  const _BandLegend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        _LegendDot(color: AppColors.mint, label: '0.8–1.3 sweet spot'),
        _LegendDot(color: AppColors.coral, label: '>1.5 danger'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.45), shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _AcwrLineChart extends StatelessWidget {
  final List<RiskHistoryPoint> points;

  const _AcwrLineChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].acwr),
    ];
    final maxAcwr = points.map((p) => p.acwr).reduce((a, b) => a > b ? a : b);
    final maxY = (maxAcwr < 1.8 ? 1.8 : maxAcwr + 0.2).clamp(1.8, 3.0);
    final dateFmt = DateFormat('M/d');

    return ResponsiveChartFrame(
      maxHeight: 260,
      minHeight: 160,
      builder: (context, size) {
        final reservedLeft = ResponsiveChartFrame.leftTitleSize(size.width);
        return LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY.toDouble(),
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          rangeAnnotations: RangeAnnotations(
            horizontalRangeAnnotations: [
              HorizontalRangeAnnotation(
                y1: 0.8,
                y2: 1.3,
                color: AppColors.mint.withValues(alpha: 0.14),
              ),
              HorizontalRangeAnnotation(
                y1: 1.5,
                y2: maxY.toDouble(),
                color: AppColors.coral.withValues(alpha: 0.14),
              ),
            ],
          ),
          extraLinesData: ExtraLinesData(
            extraLinesOnTop: true,
            horizontalLines: [
              HorizontalLine(
                y: 0.8,
                color: AppColors.mint.withValues(alpha: 0.7),
                strokeWidth: 1,
                dashArray: [6, 4],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  style: const TextStyle(fontSize: 9, color: AppColors.mint),
                  labelResolver: (_) => '0.8',
                ),
              ),
              HorizontalLine(
                y: 1.3,
                color: AppColors.mint.withValues(alpha: 0.7),
                strokeWidth: 1,
                dashArray: [6, 4],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  style: const TextStyle(fontSize: 9, color: AppColors.mint),
                  labelResolver: (_) => '1.3',
                ),
              ),
              HorizontalLine(
                y: 1.5,
                color: AppColors.coral.withValues(alpha: 0.9),
                strokeWidth: 1.5,
                dashArray: [6, 4],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  style: const TextStyle(fontSize: 9, color: AppColors.coral),
                  labelResolver: (_) => size.width < 360 ? '1.5' : '1.5 danger',
                ),
              ),
            ],
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 0.5,
            getDrawingHorizontalLine: (v) => FlLine(
              color: AppColors.border.withValues(alpha: 0.6),
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
                interval: 0.5,
                getTitlesWidget: (value, meta) => Text(
                  value.toStringAsFixed(1),
                  style: TextStyle(fontSize: 9, color: AppColors.textMuted),
                ),
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
                  '${dateFmt.format(p.date)}\nACWR ${p.acwr.toStringAsFixed(2)}\n${p.recoveryTrend}',
                  TextStyle(color: AppColors.textPrimary, fontSize: 12),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppColors.amber,
              barWidth: 2.5,
              dotData: const FlDotData(show: true),
            ),
          ],
        ),
        duration: Duration.zero,
      );
      },
    );
  }
}

class _FatigueLineChart extends StatelessWidget {
  final List<CheckIn> checkIns;

  const _FatigueLineChart({required this.checkIns});

  @override
  Widget build(BuildContext context) {
    final chronological = List<CheckIn>.from(checkIns)
      ..sort((a, b) => a.date.compareTo(b.date));
    final spots = <FlSpot>[
      for (var i = 0; i < chronological.length; i++)
        FlSpot(i.toDouble(), chronological[i].fatigueScore.toDouble()),
    ];
    final dateFmt = DateFormat('M/d');

    return ResponsiveChartFrame(
      maxHeight: 180,
      minHeight: 130,
      heightFactor: 0.5,
      builder: (context, size) {
        final reservedLeft = ResponsiveChartFrame.leftTitleSize(size.width, wide: 22, narrow: 18);
        return LineChart(
        LineChartData(
          minY: 1,
          maxY: 5,
          minX: 0,
          maxX: (chronological.length - 1).toDouble(),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y: 4,
                color: AppColors.coral.withValues(alpha: 0.6),
                dashArray: [4, 4],
                strokeWidth: 1,
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  style: const TextStyle(fontSize: 9, color: AppColors.coral),
                  labelResolver: (_) => 'elevated',
                ),
              ),
            ],
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (v) => FlLine(
              color: AppColors.border.withValues(alpha: 0.6),
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
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: TextStyle(fontSize: 9, color: AppColors.textMuted),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: (chronological.length / 4).clamp(1, 7).toDouble(),
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= chronological.length) return const SizedBox.shrink();
                  return Text(
                    dateFmt.format(chronological[i].date),
                    style: TextStyle(fontSize: 9, color: AppColors.textMuted),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              color: AppColors.coral,
              barWidth: 2,
              dotData: const FlDotData(show: true),
            ),
          ],
        ),
        duration: Duration.zero,
      );
      },
    );
  }
}

class _WhyCard extends StatelessWidget {
  final RiskResult result;

  const _WhyCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
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
            'WHY THIS CALL',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            (result.riskLevelReasoningLLM != null && result.riskLevelReasoningLLM!.isNotEmpty)
                ? result.riskLevelReasoningLLM!
                : result.reason,
            style: const TextStyle(height: 1.45),
          ),
        ],
      ),
    );
  }
}
