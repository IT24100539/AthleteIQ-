import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/athlete.dart';
import '../models/coach_alert.dart';
import '../models/risk_result.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/coach_roster_sort.dart';
import '../widgets/async_body.dart';
import '../widgets/risk_chip.dart';
import 'coach_dashboard_screen.dart';
import 'coach_weekly_reports_screen.dart';
import 'connect_coach_screen.dart';

class CoachRosterScreen extends StatefulWidget {
  final String coachUid;
  const CoachRosterScreen({super.key, required this.coachUid});

  @override
  State<CoachRosterScreen> createState() => _CoachRosterScreenState();
}

class _CoachRosterScreenState extends State<CoachRosterScreen> {
  final _fs = FirestoreService();
  String _query = '';
  String? _inviteCode;

  final Map<String, RiskResult?> _riskByUid = {};
  final Map<String, DateTime?> _lastCheckInByUid = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  List<AthleteProfile> _trackedAthletes = [];
  Timer? _rosterPaintTimer;

  @override
  void initState() {
    super.initState();
    _loadInviteCode();
  }

  @override
  void dispose() {
    _rosterPaintTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _loadInviteCode() async {
    final code = await _fs.getCoachInviteCode(widget.coachUid);
    if (mounted) setState(() => _inviteCode = code);
  }

  void _copyInviteCode() {
    if (_inviteCode == null) return;
    Clipboard.setData(ClipboardData(text: _inviteCode!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite code copied')),
    );
  }

  void _syncAthleteSubscriptions(List<AthleteProfile> athletes) {
    if (_sameAthleteSet(_trackedAthletes, athletes)) return;

    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _riskByUid.clear();
    _lastCheckInByUid.clear();
    _trackedAthletes = List<AthleteProfile>.from(athletes);

    for (final athlete in athletes) {
      _subscriptions.add(
        _fs.latestRiskResult(athlete.uid).listen((risk) {
          if (!mounted) return;
          _riskByUid[athlete.uid] = risk;
          _scheduleRosterPaint();
        }, onError: ignoreStreamError),
      );
      _subscriptions.add(
        _fs.latestCheckInDate(athlete.uid).listen((date) {
          if (!mounted) return;
          _lastCheckInByUid[athlete.uid] = date;
          _scheduleRosterPaint();
        }, onError: ignoreStreamError),
      );
    }
  }

  void _scheduleRosterPaint() {
    _rosterPaintTimer?.cancel();
    _rosterPaintTimer = Timer(const Duration(milliseconds: 50), () {
      if (mounted) setState(() {});
    });
  }

  bool _sameAthleteSet(List<AthleteProfile> a, List<AthleteProfile> b) {
    if (a.length != b.length) return false;
    final aIds = a.map((x) => x.uid).toSet();
    return b.every((x) => aIds.contains(x.uid));
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your athletes'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Weekly reports',
            icon: const Icon(Icons.calendar_view_week_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CoachWeeklyReportsScreen(coachUid: widget.coachUid),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: CoachInviteCard(
              inviteCode: _inviteCode,
              onCopy: _copyInviteCode,
            ),
          ),
          StreamBuilder<List<CoachAlert>>(
            stream: _fs.streamCoachAlerts(widget.coachUid),
            builder: (context, alertSnap) {
              if (alertSnap.hasError) return const SizedBox.shrink();
              final high = (alertSnap.data ?? [])
                  .where((a) => a.isHighPain || a.isRiskSpike)
                  .take(5)
                  .toList();
              if (high.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 140),
                      child: SingleChildScrollView(
                        child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.riskHighBg,
                    border: Border.all(color: AppColors.coral.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NEEDS REVIEW — RISK SPIKE OR HIGH PAIN',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.coral,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final alert in high)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '${alert.athleteName}: ${alert.summary}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                              height: 1.3,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                      ),
                    ),
                  );
            },
          ),
          Expanded(
            child: StreamBuilder<List<AthleteProfile>>(
              stream: _fs.rosterForCoach(widget.coachUid),
              builder: (context, snapshot) {
                final blocked = asyncBody(
                  snapshot,
                  heading: 'Could not load your roster',
                );
                if (blocked != null) return blocked;

                final roster = snapshot.data ?? [];
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _syncAthleteSubscriptions(roster);
                });

                final needingReview = countAthletesNeedingReview(roster, _riskByUid);
                final total = roster.length;
                final filtered = roster
                    .where((a) => a.name.toLowerCase().contains(_query.toLowerCase()))
                    .toList();
                final sorted = sortCoachRoster(filtered, _riskByUid, _lastCheckInByUid);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Your team', style: Theme.of(context).textTheme.titleLarge),
                                const SizedBox(height: 2),
                                Text(
                                  total == 0
                                      ? 'No athletes yet'
                                      : '$total ${total == 1 ? 'athlete' : 'athletes'} · sorted by risk',
                                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          if (needingReview > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.riskHighBg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.coral.withValues(alpha: 0.45),
                                ),
                              ),
                              child: Text(
                                '$needingReview needing review',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.coral,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search athletes…',
                          prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textFaint),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    Expanded(
                      child: sorted.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'No athletes linked yet.\nShare your invite code above — athletes enter it under Connect coach.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppColors.textMuted),
                                ),
                              ),
                            )
                          : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  cacheExtent: 480,
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final athlete = sorted[i];
                    final risk = _riskByUid[athlete.uid];
                    final level = risk?.riskLevel ?? 'LOW';
                    final needsReview = athleteNeedsReview(athlete, risk);
                    final lastCheckIn = _lastCheckInByUid[athlete.uid];

                    return InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CoachDashboardScreen(athlete: athlete),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              backgroundColor: AppColors.surface,
                              child: Text(
                                _initials(athlete.name),
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    athlete.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontSize: 15,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      athlete.sportsLabel.isNotEmpty
                                          ? athlete.sportsLabel
                                          : 'Sport not set',
                                      if (lastCheckIn != null)
                                        'Last log ${_formatRelativeDate(lastCheckIn)}',
                                    ].join(' · '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      if (needsReview)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.riskHighBg,
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(
                                              color: AppColors.coral.withValues(alpha: 0.4),
                                            ),
                                          ),
                                          child: const Text(
                                            'REVIEW',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.coral,
                                            ),
                                          ),
                                        ),
                                      if ((athlete.latestPainUrgency ?? '').toUpperCase() ==
                                          'HIGH')
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.riskHighBg,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: AppColors.coral.withValues(alpha: 0.5),
                                            ),
                                          ),
                                          child: const Text(
                                            'PAIN',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.coral,
                                            ),
                                          ),
                                        ),
                                      RiskChip(level: level),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatRelativeDate(DateTime date) {
    final days = DateTime.now().difference(date).inDays;
    if (days == 0) return 'today';
    if (days == 1) return 'yesterday';
    return '$days days ago';
  }
}
