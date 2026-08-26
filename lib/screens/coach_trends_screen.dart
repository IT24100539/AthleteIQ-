import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/athlete.dart';
import '../models/checkin.dart';
import '../models/risk_result.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/risk_signals.dart';
import '../widgets/async_body.dart';
import '../widgets/responsive_chart_frame.dart';
import '../widgets/risk_chip.dart';

/// Team-wide snapshot + per-athlete multi-week ACWR and load trends.
class CoachTrendsScreen extends StatefulWidget {
  final String coachUid;
  final String? initialAthleteUid;

  const CoachTrendsScreen({
    super.key,
    required this.coachUid,
    this.initialAthleteUid,
  });

  @override
  State<CoachTrendsScreen> createState() => _CoachTrendsScreenState();
}

class _CoachTrendsScreenState extends State<CoachTrendsScreen> {
  final _fs = FirestoreService();
  int _scopeIndex = 0; // 0 = team, 1 = athlete
  String? _selectedAthleteUid;
  List<AthleteProfile> _athletes = [];

  final Map<String, RiskResult?> _latestByUid = {};
  final Map<String, List<RiskHistoryPoint>> _historyByUid = {};
  final Map<String, List<CheckIn>> _checkInsByUid = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  StreamSubscription<dynamic>? _selectedCheckInSub;
  Timer? _trendsPaintTimer;

  @override
  void initState() {
    super.initState();
    _selectedAthleteUid = widget.initialAthleteUid;
    if (widget.initialAthleteUid != null) _scopeIndex = 1;
  }

  @override
  void dispose() {
    _trendsPaintTimer?.cancel();
    _selectedCheckInSub?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  void _resubscribe(List<AthleteProfile> athletes) {
    if (_sameAthleteSet(athletes, _athletes)) return;
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _athletes = athletes;
    _latestByUid.clear();
    _historyByUid.clear();
    _checkInsByUid.clear();

    if (_selectedAthleteUid == null && athletes.isNotEmpty) {
      _selectedAthleteUid = athletes.first.uid;
    } else if (_selectedAthleteUid != null &&
        athletes.every((a) => a.uid != _selectedAthleteUid)) {
      _selectedAthleteUid = athletes.isEmpty ? null : athletes.first.uid;
    }

    for (final athlete in athletes) {
      _subscriptions.add(
        _fs.latestRiskResult(athlete.uid).listen((r) {
          if (!mounted) return;
          _latestByUid[athlete.uid] = r;
          _scheduleTrendsPaint();
        }, onError: ignoreStreamError),
      );
      _subscriptions.add(
        _fs.streamRiskHistory(athlete.uid).listen((pts) {
          if (!mounted) return;
          _historyByUid[athlete.uid] = pts;
          _scheduleTrendsPaint();
        }, onError: ignoreStreamError),
      );
    }
    _listenSelectedCheckIns(_selectedAthleteUid);
  }

  void _listenSelectedCheckIns(String? uid) {
    _selectedCheckInSub?.cancel();
    _selectedCheckInSub = null;
    if (uid == null) return;
    _selectedCheckInSub = _fs.recentCheckIns(uid, days: 35).listen((cis) {
      if (!mounted) return;
      _checkInsByUid[uid] = cis;
      _scheduleTrendsPaint();
    }, onError: ignoreStreamError);
  }

  void _scheduleTrendsPaint() {
    _trendsPaintTimer?.cancel();
    _trendsPaintTimer = Timer(const Duration(milliseconds: 50), () {
      if (mounted) setState(() {});
    });
  }

  bool _sameAthleteSet(List<AthleteProfile> a, List<AthleteProfile> b) {
    if (a.length != b.length) return false;
    final ids = a.map((x) => x.uid).toSet();
    return b.every((x) => ids.contains(x.uid));
  }

  List<RiskHistoryPoint> _athleteSeries(String uid) {
    final stored = _historyByUid[uid] ?? [];
    final checkIns = _checkInsByUid[uid] ?? [];
    final latest = _latestByUid[uid];
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

  List<_TeamTrendPoint> _teamAverageSeries() {
    final byDay = <DateTime, List<double>>{};
    for (final athlete in _athletes) {
      if (!athlete.privacySettings.trainingLogs) continue;
      for (final p in _athleteSeries(athlete.uid)) {
        final day = DateTime(p.date.year, p.date.month, p.date.day);
        byDay.putIfAbsent(day, () => []).add(p.acwr);
      }
    }
    return byDay.entries
        .map((e) => _TeamTrendPoint(
              date: e.key,
              avgAcwr: e.value.reduce((a, b) => a + b) / e.value.length,
            ))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trends'),
        centerTitle: true,
      ),
      body: StreamBuilder<List<AthleteProfile>>(
        stream: _fs.rosterForCoach(widget.coachUid),
        builder: (context, snap) {
          final blocked = asyncBody(
            snap,
            heading: 'Could not load trends',
          );
          if (blocked != null) return blocked;

          final athletes = snap.data ?? [];
          _resubscribe(athletes);

          if (athletes.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Add athletes to your roster to see team and individual trends.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenEdge),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Team')),
                    ButtonSegment(value: 1, label: Text('Athlete')),
                  ],
                  selected: {_scopeIndex},
                  onSelectionChanged: (s) => setState(() => _scopeIndex = s.first),
                ),
                const SizedBox(height: 16),
                if (_scopeIndex == 0) _buildTeamView(context, athletes) else _buildAthleteView(context, athletes),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTeamView(BuildContext context, List<AthleteProfile> athletes) {
    final teamSeries = _teamAverageSeries();
    final total7d = athletes
        .map((a) => _latestByUid[a.uid]?.trainingLoad7d ?? 0)
        .fold<double>(0, (a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryTile(
                label: 'Team 7d load',
                value: total7d.toStringAsFixed(0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryTile(
                label: 'Athletes tracked',
                value: '${athletes.length}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'CURRENT ACWR — ROSTER',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Latest snapshot per athlete. Pick Athlete for multi-week ACWR and load charts.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
        ),
        const SizedBox(height: 12),
        ...athletes.map((a) {
          final latest = _latestByUid[a.uid];
          final acwr = latest?.acwr ?? 0;
          return _RosterAcwrRow(
            name: a.name,
            acwr: acwr,
            riskLevel: latest?.riskLevel,
            load7d: latest?.trainingLoad7d,
          );
        }),
        const SizedBox(height: 24),
        Text(
          'TEAM AVG ACWR OVER TIME',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        if (teamSeries.length < 2)
          Text(
            'Need more dated risk snapshots across the roster for a team trend line.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          )
        else
          _TeamAcwrChart(points: teamSeries),
      ],
    );
  }

  Widget _buildAthleteView(BuildContext context, List<AthleteProfile> athletes) {
    final uid = _selectedAthleteUid ?? athletes.first.uid;
    final athlete = athletes.firstWhere((a) => a.uid == uid);
    final series = _athleteSeries(uid);
    final checkIns = _checkInsByUid[uid] ?? [];
    final latest = _latestByUid[uid];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: uid,
          decoration: const InputDecoration(
            labelText: 'Athlete',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final a in athletes)
              DropdownMenuItem(
                value: a.uid,
                child: Text(a.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            setState(() => _selectedAthleteUid = v);
            _listenSelectedCheckIns(v);
          },
        ),
        const SizedBox(height: 12),
        if (latest != null)
          Row(
            children: [
              RiskChip(level: latest.riskLevel),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                athlete.privacySettings.trainingLogs
                    ? 'ACWR ${latest.acwr.toStringAsFixed(2)} · 7d load ${latest.trainingLoad7d.toStringAsFixed(0)}'
                    : 'Training logs not shared',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              ),
            ],
          ),
        const SizedBox(height: 16),
        Text(
          'ACWR OVER WEEKS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        if (!athlete.privacySettings.trainingLogs)
          Text(
            'This athlete is not sharing training logs, so ACWR history is hidden.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          )
        else if (series.length < 2)
          Text(
            'Not enough history yet — dated riskResults snapshots fill this after recalculation.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          )
        else
          _AthleteAcwrChart(points: series, athleteName: athlete.name),
        const SizedBox(height: 24),
        Text(
          'DAILY TRAINING LOAD (35 DAYS)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        if (!athlete.privacySettings.trainingLogs)
          Text(
            'Training logs are not shared with you.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          )
        else if (checkIns.isEmpty)
          Text(
            'No check-ins in the last 35 days.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          )
        else
          _DailyLoadChart(checkIns: checkIns.reversed.toList()),
      ],
    );
  }
}

class _TeamTrendPoint {
  final DateTime date;
  final double avgAcwr;

  const _TeamTrendPoint({required this.date, required this.avgAcwr});
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _RosterAcwrRow extends StatelessWidget {
  final String name;
  final double acwr;
  final String? riskLevel;
  final double? load7d;

  const _RosterAcwrRow({
    required this.name,
    required this.acwr,
    this.riskLevel,
    this.load7d,
  });

  Color get _barColor {
    if (acwr > 1.5) return AppColors.coral;
    if (acwr > 1.3) return AppColors.amber;
    if (acwr >= 0.8) return AppColors.mint;
    return AppColors.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    final widthFactor = (acwr / 2.0).clamp(0.05, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                if (riskLevel != null) RiskChip(level: riskLevel!),
                const SizedBox(width: 8),
                Text(
                  acwr.toStringAsFixed(2),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _barColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: widthFactor,
                minHeight: 8,
                backgroundColor: AppColors.border,
                color: _barColor,
              ),
            ),
            if (load7d != null) ...[
              const SizedBox(height: 6),
              Text(
                '7d load ${load7d!.toStringAsFixed(0)}',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TeamAcwrChart extends StatelessWidget {
  final List<_TeamTrendPoint> points;

  const _TeamAcwrChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].avgAcwr),
    ];
    final maxAcwr = points.map((p) => p.avgAcwr).reduce((a, b) => a > b ? a : b);
    final maxY = (maxAcwr < 1.8 ? 1.8 : maxAcwr + 0.2).clamp(1.8, 3.0);
    final dateFmt = DateFormat('M/d');

    return ResponsiveChartFrame(
      maxHeight: 220,
      minHeight: 150,
      builder: (context, size) {
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
            ],
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: AppColors.border.withValues(alpha: 0.5), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (v, _) => Text(
                  v.toStringAsFixed(1),
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: (points.length / 5).ceilToDouble().clamp(1, 999),
                getTitlesWidget: (v, _) {
                  final i = v.round();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  return Text(
                    dateFmt.format(points[i].date),
                    style: TextStyle(fontSize: 9, color: AppColors.textMuted),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppColors.mint,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
        duration: Duration.zero,
      );
      },
    );
  }
}

class _AthleteAcwrChart extends StatelessWidget {
  final List<RiskHistoryPoint> points;
  final String athleteName;

  const _AthleteAcwrChart({required this.points, required this.athleteName});

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].acwr),
    ];
    final maxAcwr = points.map((p) => p.acwr).reduce((a, b) => a > b ? a : b);
    final maxY = (maxAcwr < 1.8 ? 1.8 : maxAcwr + 0.2).clamp(1.8, 3.0);
    final dateFmt = DateFormat('M/d');

    return ResponsiveChartFrame(
      maxHeight: 260,
      minHeight: 160,
      builder: (context, size) {
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
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (v, _) => Text(
                  v.toStringAsFixed(1),
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: (points.length / 5).ceilToDouble().clamp(1, 999),
                getTitlesWidget: (v, _) {
                  final i = v.round();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  return Text(
                    dateFmt.format(points[i].date),
                    style: TextStyle(fontSize: 9, color: AppColors.textMuted),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppColors.mint,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
        duration: Duration.zero,
      );
      },
    );
  }
}

class _DailyLoadChart extends StatelessWidget {
  final List<CheckIn> checkIns;

  const _DailyLoadChart({required this.checkIns});

  @override
  Widget build(BuildContext context) {
    final loads = checkIns.map((c) => c.trainingLoad ?? 0).toList();
    final maxLoad = loads.fold<double>(0, (a, b) => a > b ? a : b);
    const chartHeight = 120.0;
    final dateFmt = DateFormat('M/d');

    return Container(
      height: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < checkIns.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: maxLoad > 0 ? (loads[i] / maxLoad) * chartHeight : 4,
                    constraints: const BoxConstraints(minHeight: 4),
                    decoration: BoxDecoration(
                      color: loads[i] > 0 ? AppColors.mint : AppColors.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (i % 5 == 0)
                    Text(
                      dateFmt.format(checkIns[i].date),
                      style: TextStyle(fontSize: 8, color: AppColors.textMuted),
                    )
                  else
                    const SizedBox(height: 10),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
