import 'package:flutter/material.dart';
import '../models/athlete.dart';
import '../models/checkin.dart';
import '../models/risk_result.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/approval_gate.dart';
import '../utils/this_week_plan.dart';
import '../utils/stream_fallback.dart';
import '../utils/wearable_sync_status.dart';
import '../widgets/async_body.dart';
import '../widgets/empty_state.dart';
import '../widgets/hero_card.dart';
import '../widgets/stat_card.dart';
import 'checkin_screen.dart';
import 'connect_device_screen.dart';
import 'manual_daily_log_screen.dart';
import 'my_alerts_screen.dart';
import 'my_performance_screen.dart';
import 'no_data_yet_screen.dart';
import 'report_pain_screen.dart';
import 'sync_failed_screen.dart';

class AthleteHomeScreen extends StatefulWidget {
  final String athleteUid;

  const AthleteHomeScreen({super.key, required this.athleteUid});

  @override
  State<AthleteHomeScreen> createState() => _AthleteHomeScreenState();
}

class _AthleteHomeScreenState extends State<AthleteHomeScreen> {
  final _fs = FirestoreService();
  late final Stream<AthleteProfile> _profileStream;
  late final Stream<RiskResult?> _riskStream;
  late final Stream<List<CheckIn>> _checkInStream;
  late final Stream<Map<String, Map<String, dynamic>>> _deviceStream;

  @override
  void initState() {
    super.initState();
    final uid = widget.athleteUid;
    _profileStream = emitOnError(
      _fs.athleteProfile(uid),
      AthleteProfile.fromMap(uid, {}),
    );
    _riskStream = emitOnError(_fs.latestRiskResult(uid), null);
    _checkInStream = emitOnError(
      _fs.recentCheckIns(uid, days: 10),
      const <CheckIn>[],
    );
    _deviceStream = emitOnError(
      _fs.streamDevices(uid),
      const <String, Map<String, dynamic>>{},
    );
  }

  void _openConnectDevices(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectDeviceScreen(
          athleteUid: widget.athleteUid,
          isFromSettings: true,
        ),
      ),
    );
  }

  void _openReportPain(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReportPainScreen(athleteUid: widget.athleteUid),
      ),
    );
  }

  void _openAlerts(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MyAlertsScreen(athleteUid: widget.athleteUid),
      ),
    );
  }

  void _openManualLog(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManualDailyLogScreen(athleteUid: widget.athleteUid),
      ),
    );
  }

  void _openPerformanceDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MyPerformanceScreen(athleteUid: widget.athleteUid),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AthleteIQ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none, size: 20),
            tooltip: 'Alerts',
            onPressed: () => _openAlerts(context),
          ),
          IconButton(
            icon: const Icon(Icons.watch_outlined, size: 20),
            tooltip: 'Connected Devices',
            onPressed: () => _openConnectDevices(context),
          ),
        ],
      ),
      body: StreamBuilder<AthleteProfile>(
        stream: _profileStream,
        builder: (context, profileSnap) {
          final profile = profileSnap.data;
          final activeDevice = profile?.activeDevice;
          final deviceTier = profile?.deviceTier ?? 'tier3';

          return StreamBuilder<RiskResult?>(
            stream: _riskStream,
            builder: (context, snapshot) {
              final result = snapshot.data;
              // Section 6 / 11 / 17.1 — only approved | modified reach the athlete.
              final isReleased =
                  recommendationReleasedToAthlete(result?.recommendationStatus);

              return StreamBuilder<List<CheckIn>>(
                stream: _checkInStream,
                builder: (context, checkInSnap) {
                  return StreamBuilder<Map<String, Map<String, dynamic>>>(
                    stream: _deviceStream,
                    builder: (context, deviceSnap) {
                      final blocked = asyncBodyAny(
                        [profileSnap, snapshot, checkInSnap, deviceSnap],
                        heading: 'Could not load your home screen',
                      );
                      if (blocked != null) return blocked;

                      final checkIns = checkInSnap.data ?? [];
                      final devices = deviceSnap.data ?? {};
                      final syncIssue = deviceTier == 'tier3'
                          ? null
                          : findWearableSyncIssue(devices);

                      if (syncIssue != null) {
                        return SyncFailedScreen(
                          issue: syncIssue,
                          onReconnect: () => _openConnectDevices(context),
                          onReportPain: () => _openReportPain(context),
                        );
                      }

                      if (checkIns.isEmpty) {
                        return NoDataYetScreen(
                          onLogCheckIn: () => _openManualLog(context),
                          onConnectDevice: () => _openConnectDevices(context),
                        );
                      }

                      return SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.screenEdge),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GestureDetector(
                          onTap: () => _openConnectDevices(context),
                          child: Container(
            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: activeDevice != null
                                    ? AppColors.mint.withValues(alpha: 0.3)
                                    : AppColors.border,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  activeDevice != null
                                      ? Icons.watch
                                      : Icons.watch_outlined,
                                  color: activeDevice != null
                                      ? AppColors.mint
                                      : AppColors.textMuted,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                            activeDevice ?? 'No wearable connected',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: deviceTier == 'tier1'
                                                  ? AppColors.mint.withValues(alpha: 0.15)
                                                  : AppColors.surfaceAlt,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              deviceTier == 'tier1'
                                                  ? 'TIER 1 · FULL'
                                                  : (deviceTier == 'tier2'
                                                      ? 'TIER 2 · PARTIAL'
                                                      : 'TIER 3 · MANUAL'),
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                                color: deviceTier == 'tier1'
                                                    ? AppColors.mint
                                                    : AppColors.textMuted,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        activeDevice != null
                                            ? 'Auto-syncing workouts & biometrics'
                                            : 'Tap to connect Apple Watch, Health Connect, or Garmin',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right,
                                    color: AppColors.textFaint, size: 18),
                              ],
                            ),
                          ),
                        ),

                        if (!snapshot.hasData || result == null)
                          EmptyState(
                            icon: Icons.show_chart_rounded,
                            heading: 'Building your first forecast',
                            subtext:
                                'Log a few more days of training and how you feel before AthleteIQ can predict '
                                'performance or risk reliably.',
                            actionLabel: 'Log today',
                            onAction: () => _openManualLog(context),
                          )
                        else ...[
                          HeroGradientCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'TODAY',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.mint,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  isReleased
                                      ? result.recommendation
                                      : "Your coach is reviewing today's plan",
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  isReleased
                                      ? result.reason
                                      : "You'll see your personalized guidance here as soon as it's approved.",
                                  style: TextStyle(
                                      color: AppColors.textSecondary, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _ThisWeekCard(
                            checkIns: checkIns,
                            result: result,
                            onLog: () => _openManualLog(context),
                          ),
                          const SizedBox(height: 16),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _openPerformanceDetail(context),
                              borderRadius: BorderRadius.circular(AppRadius.hero),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                            child: StatCard(
                                                label: 'ACWR',
                                                value: result.acwr.toStringAsFixed(2))),
                                        const SizedBox(width: 8),
                                        Expanded(
                                            child: StatCard(
                                                label: 'Recovery',
                                                value: result.recoveryTrend)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                            child: StatCard(
                                                label: result.performanceAxisLabel,
                                                value: result.performanceDisplay)),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    const Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Text(
                                          'Performance detail',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.mint,
                                          ),
                                        ),
                                        SizedBox(width: 4),
                                        Icon(
                                          Icons.chevron_right,
                                          size: 16,
                                          color: AppColors.mint,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            CheckInScreen(athleteUid: widget.athleteUid)),
                                  ),
                                  child: const FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text("Log check-in"),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                onPressed: () => _openReportPain(context),
                                icon: const Icon(Icons.warning_amber_rounded,
                                    color: AppColors.coral, size: 18),
                                label: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text('Report pain',
                                    style: TextStyle(color: AppColors.coral)),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                      color: AppColors.coral.withValues(alpha: 0.4)),
                                ),
                              ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                    },
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

class _ThisWeekCard extends StatelessWidget {
  final List<CheckIn> checkIns;
  final RiskResult result;
  final VoidCallback onLog;

  const _ThisWeekCard({
    required this.checkIns,
    required this.result,
    required this.onLog,
  });

  @override
  Widget build(BuildContext context) {
    final days = buildThisWeekDays(
      now: DateTime.now(),
      checkIns: checkIns,
      result: result,
    );
    final hasData = thisWeekHasRealData(days);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This week',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'From your check-ins this week. Today uses the coach-released recommendation if you have not logged yet.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35),
          ),
          const SizedBox(height: 12),
          if (!hasData)
            EmptyState(
              icon: Icons.calendar_view_week_outlined,
              heading: 'No week data yet',
              subtext:
                  'There is no check-in this week and no released recommendation to show. Log a session or wait for your coach to send a plan — we will not invent Rest / Light run rows.',
              actionLabel: 'Log today',
              onAction: onLog,
            )
          else
            for (final day in days) _PlanDayRow(day: day),
        ],
      ),
    );
  }
}

class _PlanDayRow extends StatelessWidget {
  final ThisWeekDay day;

  const _PlanDayRow({required this.day});

  Color get _dot {
    switch (day.kind) {
      case ThisWeekDayKind.trained:
        return AppColors.mint;
      case ThisWeekDayKind.plan:
        return AppColors.amber;
      case ThisWeekDayKind.rest:
        return AppColors.textMuted;
      case ThisWeekDayKind.notLogged:
      case ThisWeekDayKind.upcoming:
        return AppColors.border;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _dot),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 36,
            child: Text(
              day.dayLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              day.activity,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: day.isRest ||
                        day.kind == ThisWeekDayKind.notLogged ||
                        day.kind == ThisWeekDayKind.upcoming
                    ? AppColors.textMuted
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
