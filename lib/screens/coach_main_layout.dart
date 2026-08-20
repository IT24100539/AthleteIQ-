import 'dart:async';

import 'package:flutter/material.dart';
import '../models/athlete.dart';
import '../models/chat_message.dart';
import '../models/coach_alert.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/coach_inbox.dart';
import '../widgets/async_body.dart';
import 'coach_alerts_screen.dart';
import 'coach_inbox_screen.dart';
import 'coach_roster_screen.dart';
import 'coach_settings_screen.dart';
import 'coach_trends_screen.dart';

/// Coach shell — roster, inbox, trends, alerts, and settings.
/// Per-athlete drill-down stays a push route from the roster.
class CoachMainLayout extends StatefulWidget {
  final String coachUid;
  final int initialTab;

  const CoachMainLayout({
    super.key,
    required this.coachUid,
    this.initialTab = 0,
  });

  @override
  State<CoachMainLayout> createState() => _CoachMainLayoutState();
}

class _CoachMainLayoutState extends State<CoachMainLayout> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      CoachRosterScreen(coachUid: widget.coachUid),
      CoachInboxScreen(coachUid: widget.coachUid),
      CoachTrendsScreen(coachUid: widget.coachUid),
      CoachAlertsScreen(coachUid: widget.coachUid),
      CoachSettingsScreen(coachUid: widget.coachUid),
    ];

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: StreamBuilder(
        stream: FirestoreService().streamCoachAlerts(widget.coachUid),
        builder: (context, snapshot) {
          final alerts = snapshot.hasError ? const <CoachAlert>[] : (snapshot.data ?? []);
          final urgentCount = alerts
              .where((a) => a.isHighPain || a.isRiskSpike)
              .length;

          return Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (i) => setState(() => _currentIndex = i),
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.groups_outlined, size: 20),
                  label: 'Roster',
                ),
                BottomNavigationBarItem(
                  icon: _InboxNavIcon(coachUid: widget.coachUid),
                  label: 'Inbox',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.show_chart_outlined, size: 20),
                  label: 'Trends',
                ),
                BottomNavigationBarItem(
                  icon: _BadgedIcon(
                    icon: Icons.notifications_none,
                    count: urgentCount,
                  ),
                  label: 'Alerts',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline, size: 20),
                  label: 'Profile',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InboxNavIcon extends StatefulWidget {
  final String coachUid;

  const _InboxNavIcon({required this.coachUid});

  @override
  State<_InboxNavIcon> createState() => _InboxNavIconState();
}

class _InboxNavIconState extends State<_InboxNavIcon> {
  final _fs = FirestoreService();
  List<AthleteProfile> _athletes = [];
  final Map<String, ChatMessage?> _latestByUid = {};
  final Map<String, DateTime?> _lastReadByUid = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  void _resubscribe(List<AthleteProfile> athletes) {
    if (athletes.length == _athletes.length &&
        athletes.every((a) => _athletes.any((b) => b.uid == a.uid))) {
      return;
    }
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _athletes = athletes;
    _latestByUid.clear();
    _lastReadByUid.clear();
    for (final athlete in athletes) {
      _subscriptions.add(
        _fs.streamLatestCoachMessage(athlete.uid).listen((msg) {
          if (mounted) setState(() => _latestByUid[athlete.uid] = msg);
        }, onError: ignoreStreamError),
      );
      _subscriptions.add(
        _fs.streamInboxLastRead(widget.coachUid, athlete.uid).listen((at) {
          if (mounted) setState(() => _lastReadByUid[athlete.uid] = at);
        }, onError: ignoreStreamError),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AthleteProfile>>(
      stream: _fs.rosterForCoach(widget.coachUid),
      builder: (context, snap) {
        if (!snap.hasError) {
          _resubscribe(snap.data ?? []);
        }
        final count = _athletes.where((a) {
          return coachThreadIsUnread(_latestByUid[a.uid], _lastReadByUid[a.uid]);
        }).length;
        return _BadgedIcon(icon: Icons.chat_bubble_outline, count: count);
      },
    );
  }
}

class _BadgedIcon extends StatelessWidget {
  final IconData icon;
  final int count;

  const _BadgedIcon({required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return Icon(icon, size: 20);
    }

    final label = count > 9 ? '9+' : '$count';
    return Badge(
      label: Text(
        label,
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
      ),
      backgroundColor: AppColors.coral,
      child: Icon(icon, size: 20),
    );
  }
}
